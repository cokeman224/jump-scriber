defmodule SocialScribeWeb.ChatLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Accounts
  alias SocialScribe.CrmChat
  alias SocialScribe.HubspotApi
  alias SocialScribe.SalesforceApi

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    hubspot_cred = Accounts.get_user_hubspot_credential(user.id)
    salesforce_cred = Accounts.get_user_salesforce_credential(user.id)
    crm_provider = default_crm_provider(hubspot_cred, salesforce_cred)

    socket =
      socket
      |> assign(:page_title, "Ask Anything")
      |> assign(:active_tab, :chat)
      |> assign(:messages, [])
      |> assign(:input_message, "")
      |> assign(:tagged_contact, nil)
      |> assign(:tagged_contact_id, nil)
      |> assign(:crm_provider, crm_provider)
      |> assign(:hubspot_credential, hubspot_cred)
      |> assign(:salesforce_credential, salesforce_cred)
      |> assign(:contact_picker_open, false)
      |> assign(:contact_search_query, "")
      |> assign(:contact_search_results, [])
      |> assign(:contact_search_loading, false)
      |> assign(:sending, false)
      |> assign(:timestamp, format_timestamp(DateTime.utc_now()))

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => text}, socket) do
    text = String.trim(text)
    if text == "" do
      {:noreply, socket}
    else
      user = socket.assigns.current_user
      tagged_id = socket.assigns.tagged_contact_id
      provider = socket.assigns.crm_provider

      user_msg = %{role: :user, content: text, tagged_contact: socket.assigns.tagged_contact}
      messages = socket.assigns.messages ++ [user_msg]

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:input_message, "")
        |> assign(:tagged_contact, nil)
        |> assign(:tagged_contact_id, nil)
        |> assign(:sending, true)

      send(self(), {:answer_question, text, tagged_id, provider, user.id})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => value}, socket) do
    socket = assign(socket, input_message: value || "")
    socket =
      if socket.assigns.tagged_contact && !String.contains?(value || "", socket.assigns.tagged_contact.name) do
        assign(socket, tagged_contact: nil, tagged_contact_id: nil)
      else
        socket
      end
    {:noreply, socket}
  end

  def handle_event("add_context_click", _params, socket) do
    {:noreply, assign(socket, contact_picker_open: true, contact_search_results: [])}
  end

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)
    if String.length(query) >= 2 do
      send(self(), {:chat_contact_search, query, socket.assigns.hubspot_credential, socket.assigns.salesforce_credential})
      {:noreply, assign(socket, contact_search_query: query, contact_search_loading: true)}
    else
      {:noreply, assign(socket, contact_search_query: query, contact_search_results: [])}
    end
  end

  @impl true
  def handle_event("select_chat_contact", %{"id" => id, "provider" => provider}, socket) do
    results = socket.assigns.contact_search_results
    contact = Enum.find(results, fn c -> c.id == id and c.provider == provider end)
    if contact do
      contact_text = " " <> contact.display_name <> " (" <> provider <> ")"
      socket =
        socket
        |> assign(:tagged_contact, %{id: contact.id, name: contact.display_name, provider: provider})
        |> assign(:tagged_contact_id, contact.id)
        |> assign(:crm_provider, provider)
        |> assign(:input_message, (socket.assigns.input_message || "") <> contact_text)
        |> assign(:contact_picker_open, false)
        |> assign(:contact_search_results, [])
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_contact_picker", _params, socket) do
    {:noreply, assign(socket, contact_picker_open: false)}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => "history"}, socket) do
    {:noreply, assign(socket, active_tab: :history)}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => "chat"}, socket) do
    {:noreply, assign(socket, active_tab: :chat)}
  end

  @impl true
  def handle_info({:answer_question, text, tagged_id, provider, user_id}, socket) do
    result = CrmChat.answer_question(user_id, text, tagged_id, provider)

    socket =
      case result do
        {:ok, %{answer: answer, sources: sources}} ->
          msg = %{role: :ai, content: answer, sources: sources}
          assign(socket, messages: socket.assigns.messages ++ [msg], sending: false)

        {:error, reason} ->
          err_msg = %{role: :ai, content: "Sorry, I couldn't answer that. (#{inspect(reason)})", sources: []}
          assign(socket, messages: socket.assigns.messages ++ [err_msg], sending: false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_contact_search, query, hubspot_cred, salesforce_cred}, socket) do
    results = []
    results =
      if hubspot_cred do
        case HubspotApi.search_contacts(hubspot_cred, query) do
          {:ok, contacts} -> Enum.map(contacts, fn c -> Map.put(c, :provider, "hubspot") end) ++ results
          _ -> results
        end
      else
        results
      end

    results =
      if salesforce_cred do
        case SalesforceApi.search_contacts(salesforce_cred, query) do
          {:ok, contacts} -> Enum.map(contacts, fn c -> Map.put(c, :provider, "salesforce") end) ++ results
          _ -> results
        end
      else
        results
      end

    {:noreply, assign(socket, contact_search_results: results, contact_search_loading: false)}
  end

  defp format_timestamp(dt) do
    dt
    |> Timex.format!("%I:%M%p – %B %-d, %Y", :strftime)
    |> String.replace("AM", "am")
    |> String.replace("PM", "pm")
  end

  defp default_crm_provider(hubspot_cred, salesforce_cred) do
    cond do
      hubspot_cred != nil -> "hubspot"
      salesforce_cred != nil -> "salesforce"
      true -> nil
    end
  end
end
