defmodule SocialScribeWeb.AskAnythingSidebarLive do
  @moduledoc """
  A collapsible sidebar for "Ask Anything" chat. Slides in from the right when
  the chat toggle button is clicked.
  """
  use SocialScribeWeb, :live_view

  alias SocialScribe.Accounts
  alias SocialScribe.AskAnything
  alias SocialScribe.AskAnythingStore
  alias SocialScribe.CrmChat
  alias SocialScribe.HubspotApi
  alias SocialScribe.SalesforceApi

  @impl true
  def mount(_params, session, socket) do
    user_id = session["user_id"]
    user = Accounts.get_user!(user_id)
    hubspot_cred = Accounts.get_user_hubspot_credential(user.id)
    salesforce_cred = Accounts.get_user_salesforce_credential(user.id)
    crm_provider = default_crm_provider(hubspot_cred, salesforce_cred)

    messages = AskAnythingStore.get_messages(user_id)
    conv_id = if Enum.empty?(messages), do: nil, else: AskAnything.get_latest_conversation(user_id) |> elem(0)

    socket =
      socket
      |> assign(:open, false)
      |> assign(:current_user, user)
      |> assign(:active_tab, :chat)
      |> assign(:current_conversation_id, conv_id)
      |> assign(:messages, messages)
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
      |> assign(:history_messages, [])

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="ask-anything-sidebar-wrapper" class={[
      "fixed inset-0 sm:inset-auto sm:right-0 sm:top-0 sm:h-full z-50 flex justify-end touch-pan-y",
      !@open && "pointer-events-none",
      @open && "pointer-events-auto"
    ]} phx-hook="AskSidebarOpener">
      <%!-- Backdrop (mobile only, when open) --%>
      <div
        :if={@open}
        class="fixed inset-0 bg-black/20 sm:hidden z-40"
        phx-click="toggle"
        aria-hidden="true"
      ></div>

      <%!-- Toggle button (visible when closed) - safe-area aware --%>
      <button
        type="button"
        phx-click="toggle"
        class={[
          "flex items-center justify-center w-12 h-12 sm:w-14 sm:h-14 rounded-full transition-all duration-300 z-50 touch-manipulation min-w-[48px] min-h-[48px] pointer-events-auto",
          "hover:scale-110 active:scale-95 shadow-lg hover:shadow-xl",
          @open && "hidden",
          !@open && "fixed sm:absolute bg-gradient-to-br from-indigo-500 to-violet-600 text-white hover:from-indigo-600 hover:to-violet-700 ring-2 ring-white/20",
          !@open && "bottom-[max(1rem,env(safe-area-inset-bottom))] right-[max(1rem,env(safe-area-inset-right))] sm:bottom-8 sm:right-8"
        ]}
        aria-label="Open Ask Anything"
      >
        <.icon name="hero-chat-bubble-left-right" class="size-7 sm:size-8" />
      </button>

      <%!-- Sidebar panel - responsive width and height --%>
      <div
        id="ask-anything-panel"
        class={[
          "relative z-50 h-full w-full min-w-0 max-w-full sm:w-[380px] sm:max-w-[min(95vw,420px)] md:max-w-[min(95vw,440px)] bg-white border-l border-slate-200 shadow-xl flex flex-col transition-transform duration-300 ease-in-out overscroll-contain pointer-events-auto",
          "min-h-[100dvh] sm:min-h-0",
          @open && "translate-x-0",
          !@open && "translate-x-full absolute right-0 top-0 sm:top-0"
        ]}
      >
        <%!-- Header --%>
        <div class="flex items-center justify-between px-3 sm:px-4 md:px-5 py-3 pt-[max(0.75rem,env(safe-area-inset-top))] border-b border-slate-100 shrink-0">
          <h2 class="text-lg font-bold text-slate-800">Ask Anything</h2>
          <button
            type="button"
            phx-click="toggle"
            class="p-2 -m-2 rounded-lg text-slate-500 hover:bg-slate-100 hover:text-slate-700 transition-colors touch-manipulation min-h-[44px] min-w-[44px] flex items-center justify-center sm:min-h-0 sm:min-w-0"
            aria-label="Close sidebar"
          >
            <span class="text-2xl sm:text-3xl font-semibold">»</span>
          </button>
        </div>

        <%!-- Tabs --%>
        <div class="flex items-center gap-1 flex-wrap px-3 sm:px-4 md:px-5 pt-2 pb-3 border-b border-slate-200 shrink-0">
          <button
            type="button"
            phx-click="set_tab"
            phx-value-tab="chat"
            class={[
              "px-4 py-2.5 sm:py-2 rounded-lg text-sm font-medium transition-colors touch-manipulation",
              @active_tab == :chat && "bg-slate-200 text-slate-800 border border-slate-300",
              @active_tab != :chat && "text-slate-500 hover:bg-slate-50"
            ]}
          >
            Chat
          </button>
          <button
            type="button"
            phx-click="set_tab"
            phx-value-tab="history"
            class={[
              "px-4 py-2.5 sm:py-2 rounded-lg text-sm font-medium transition-colors touch-manipulation",
              @active_tab == :history && "bg-slate-200 text-slate-800 border border-slate-300",
              @active_tab != :history && "text-slate-500 hover:bg-slate-50"
            ]}
          >
            History
          </button>
          <button
            type="button"
            phx-click="new_conversation"
            class="ml-auto p-2 rounded-lg text-slate-500 hover:bg-slate-100 touch-manipulation min-h-[44px] min-w-[44px] flex items-center justify-center sm:min-h-0 sm:min-w-0"
            aria-label="New conversation"
          >
            <.icon name="hero-plus" class="size-5" />
          </button>
        </div>

        <%!-- Chat content --%>
        <div id="ask-chat-content" phx-hook="ScrollToBottom" class="flex-1 overflow-y-auto overflow-x-hidden overscroll-contain px-3 sm:px-4 md:px-5 py-4 flex flex-col gap-4 min-h-0 min-w-0 -webkit-overflow-scrolling-touch">
          <%= if @active_tab == :chat do %>
            <%= if Enum.empty?(@messages) do %>
              <p class="text-slate-600 text-sm py-2">
                I can answer questions about Jump meetings and data – just ask!
              </p>
            <% end %>

            <div :for={{msg, idx} <- Enum.with_index(@messages)} class="flex flex-col gap-1">
              <% prev_msg = if idx > 0, do: Enum.at(@messages, idx - 1), else: nil %>
              <%= if msg[:created_at] && show_message_timestamp?(msg, prev_msg) do %>
                <div class="flex items-center gap-3 py-1">
                  <div class="flex-1 border-t border-slate-200"></div>
                  <span class="text-xs text-slate-400 shrink-0"><%= format_timestamp(msg.created_at) %></span>
                  <div class="flex-1 border-t border-slate-200"></div>
                </div>
              <% end %>
              <%= if msg.role == :user do %>
                <div class="flex justify-end min-w-0">
                  <div class="max-w-[85%] min-w-0 rounded-lg rounded-br-md px-3 sm:px-4 py-2.5 bg-slate-200 text-slate-800 text-sm break-words">
                    <div>
                      <%= if user_message_parts(msg.content, msg.tagged_contact) do %>
                        <% {before, contact, after_} = user_message_parts(msg.content, msg.tagged_contact) %>
                        <%= before %><span class="inline-flex items-center box-decoration-slice bg-white rounded-lg pl-2.5 pr-2.5 py-px border border-slate-200 leading-relaxed"><.contact_icon contact={contact} /><%= contact.name %></span><%= after_ %>
                      <% else %>
                        <%= msg.content %>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% else %>
                <div class="flex justify-start min-w-0">
                  <div class="max-w-[85%] min-w-0 rounded-2xl rounded-bl-md px-3 sm:px-4 py-2.5 bg-white border border-slate-200 text-slate-800 text-sm shadow-sm break-words">
                    <%= if msg.tagged_contact do %>
                      <span class="inline-flex items-center box-decoration-slice bg-slate-300 rounded-lg pl-3 pr-2 py-px text-slate-700 text-sm leading-relaxed"><.contact_icon contact={msg.tagged_contact} /><%= msg.tagged_contact.name %></span>
                      <div class="mt-1 break-words"><%= strip_inline_sources(msg.content) %></div>
                    <% else %>
                      <div class="break-words"><%= strip_inline_sources(msg.content) %></div>
                    <% end %>
                    <%= if is_list(msg.sources) && Enum.any?(msg.sources) do %>
                      <div class="mt-3 pt-2 border-t border-slate-100 flex items-center gap-2">
                        <span class="text-xs font-medium text-slate-500 shrink-0">Sources</span>
                        <div class="flex flex-wrap gap-2">
                          <.source_icon :for={src <- msg.sources} source={src} />
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>

            <%= if @sending do %>
              <div class="flex justify-start min-w-0">
                <div class="rounded-2xl rounded-bl-md px-3 sm:px-4 py-2.5 bg-white border border-slate-200 text-slate-500 text-sm">
                  <.icon name="hero-arrow-path" class="size-4 animate-spin inline-block mr-2" />
                  Thinking...
                </div>
              </div>
            <% end %>
          <% else %>
            <%= if Enum.empty?(@history_messages) do %>
              <p class="text-slate-500 text-sm py-4">No saved chat history yet.</p>
            <% else %>
              <div :for={{msg, idx} <- Enum.with_index(@history_messages)} class="flex flex-col gap-1" id={"history-msg-#{idx}"}>
                <% prev_msg = if idx > 0, do: Enum.at(@history_messages, idx - 1), else: nil %>
                <%= if msg[:created_at] && show_message_timestamp?(msg, prev_msg) do %>
                  <div class="flex items-center gap-3 py-1">
                    <div class="flex-1 border-t border-slate-200"></div>
                    <span class="text-xs text-slate-400 shrink-0"><%= format_timestamp(msg.created_at) %></span>
                    <div class="flex-1 border-t border-slate-200"></div>
                  </div>
                <% end %>
                <%= if msg.role == :user do %>
                  <div class="flex justify-end min-w-0">
                    <div class="max-w-[85%] min-w-0 rounded-lg rounded-br-md px-3 sm:px-4 py-2.5 bg-slate-200 text-slate-800 text-sm break-words">
                      <div>
                        <%= if user_message_parts(msg.content, msg.tagged_contact) do %>
                          <% {before, contact, after_} = user_message_parts(msg.content, msg.tagged_contact) %>
                          <%= before %><span class="inline-flex items-center box-decoration-slice bg-white rounded-lg pl-2.5 pr-2.5 py-px border border-slate-200 leading-relaxed"><.contact_icon contact={contact} /><%= contact.name %></span><%= after_ %>
                        <% else %>
                          <%= msg.content %>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% else %>
                  <div class="flex justify-start min-w-0">
                    <div class="max-w-[85%] min-w-0 rounded-2xl rounded-bl-md px-3 sm:px-4 py-2.5 bg-white border border-slate-200 text-slate-800 text-sm shadow-sm break-words">
                      <%= if msg.tagged_contact do %>
                        <span class="inline-flex items-center box-decoration-slice bg-slate-300 rounded-lg pl-3 pr-2 py-px text-slate-700 text-sm leading-relaxed"><.contact_icon contact={msg.tagged_contact} /><%= msg.tagged_contact.name %></span>
                        <div class="mt-1 break-words"><%= strip_inline_sources(msg.content) %></div>
                      <% else %>
                        <div><%= strip_inline_sources(msg.content) %></div>
                      <% end %>
                      <%= if is_list(msg.sources) && Enum.any?(msg.sources) do %>
                        <div class="mt-3 pt-2 border-t border-slate-100 flex items-center gap-2">
                          <span class="text-xs font-medium text-slate-500 shrink-0">Sources</span>
                          <div class="flex flex-wrap gap-2">
                            <.source_icon :for={src <- msg.sources} source={src} />
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>

        <%!-- Input area --%>
        <%= if @active_tab == :chat do %>
          <div class="p-3 sm:p-4 md:p-5 pb-[max(0.75rem,env(safe-area-inset-bottom))] border-t border-slate-100 shrink-0 bg-white" id="ask-input-area" phx-hook="FocusAskInput">
            <form phx-submit="send_message" phx-change="update_input" class="space-y-2">
              <div class="rounded-xl border-2 border-ask-input bg-white p-2 sm:p-2.5 flex flex-col gap-2">
                <button
                  type="button"
                  phx-click="add_context_click"
                  class="self-start px-3 py-1.5 text-sm text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors touch-manipulation"
                >
                  @ Add context
                </button>
                <textarea
                  id="ask-message-input"
                  name="message"
                  rows="2"
                  placeholder="Ask anything about your meetings"
                  phx-hook="EnterToSubmit"
                  phx-debounce="150"
                  class="w-full px-3 py-2 border-0 focus:ring-0 focus:outline-none text-slate-800 placeholder-slate-400 text-sm resize-none min-h-[2.5rem] overflow-y-auto"
                >{@input_message}</textarea>
                <div class="flex flex-wrap items-center justify-between gap-x-2 gap-y-2">
                  <div class="flex flex-wrap items-center gap-x-2 gap-y-1.5 text-xs text-slate-700 min-w-0">
                    <span class="shrink-0">Sources</span>
                    <.source_icons />
                    <%= if @tagged_contact do %>
                      <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-xl bg-slate-100 text-slate-700 max-w-full min-w-0">
                        <.contact_icon contact={@tagged_contact} /><span class="truncate"><%= @tagged_contact.name %></span>
                        <button
                          type="button"
                          phx-click="clear_tagged_contact"
                          class="shrink-0 ml-0.5 hover:text-slate-900 rounded p-0.5 touch-manipulation"
                          aria-label="Remove contact"
                        >
                          <.icon name="hero-x-mark" class="size-3.5" />
                        </button>
                      </span>
                    <% end %>
                  </div>
                  <button
                    type="submit"
                    class="flex-shrink-0 w-9 h-9 rounded-lg bg-slate-100 border border-slate-200 hover:bg-slate-200 text-slate-600 flex items-center justify-center transition-colors touch-manipulation"
                    aria-label="Send"
                  >
                    <.icon name="hero-arrow-up" class="size-5" />
                  </button>
                </div>
              </div>
            </form>
          </div>
        <% end %>
      </div>
    </div>

    <%!-- Contact picker modal --%>
    <%= if @contact_picker_open do %>
      <div class="fixed inset-0 z-[60] flex items-end sm:items-center justify-center p-0 sm:p-4">
        <div class="absolute inset-0 bg-black/30 sm:bg-black/20" phx-click="close_contact_picker" aria-hidden="true"></div>
        <div
          class="relative bg-white rounded-t-2xl sm:rounded-xl shadow-xl max-w-md w-full sm:max-h-[70vh] flex flex-col min-h-0 w-full sm:w-auto max-h-[85dvh] sm:max-h-[70vh] pt-4 sm:pt-4 pb-[max(1rem,env(safe-area-inset-bottom))] px-4"
          phx-click-away="close_contact_picker"
        >
          <div class="flex items-center justify-between mb-3">
            <h3 class="font-semibold text-slate-800">Add contact context</h3>
            <button type="button" phx-click="close_contact_picker" class="p-2 -m-2 rounded-lg text-slate-500 hover:bg-slate-100 sm:hidden" aria-label="Close">×</button>
          </div>
          <input
            type="text"
            name="contact_query"
            value={@contact_search_query}
            placeholder="Search contacts..."
            phx-keyup="contact_search"
            phx-debounce="200"
            class="w-full px-3 py-2.5 sm:py-2 border border-slate-200 rounded-lg mb-3 text-base sm:text-sm"
          />
          <%= if @contact_search_loading do %>
            <p class="text-sm text-slate-500 py-4">Searching...</p>
          <% else %>
            <div class="overflow-y-auto flex-1 overscroll-contain -webkit-overflow-scrolling-touch space-y-0.5 sm:space-y-1 min-h-0">
              <button
                :for={c <- @contact_search_results}
                type="button"
                phx-click="select_chat_contact"
                phx-value-id={c.id}
                phx-value-provider={c.provider}
                class="w-full text-left px-3 py-3 sm:py-2 rounded-xl sm:rounded-lg hover:bg-slate-50 active:bg-slate-100 flex items-center gap-3 touch-manipulation min-h-[44px] sm:min-h-0"
              >
                <span class="w-9 h-9 sm:w-8 sm:h-8 rounded-full bg-slate-200 flex items-center justify-center text-xs font-medium text-slate-600 shrink-0">
                  <%= String.at(c.display_name || "?", 0) %>
                </span>
                <div class="min-w-0 flex-1">
                  <p class="font-medium text-slate-800 truncate"><%= c.display_name %></p>
                  <p class="text-xs text-slate-500 truncate"><%= c.email %> · <%= c.provider %></p>
                </div>
              </button>
              <%= if @contact_search_query != "" && !@contact_search_loading && Enum.empty?(@contact_search_results) do %>
                <p class="text-sm text-slate-500 py-4">No contacts found.</p>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :open, !socket.assigns.open)}
  end

  def handle_event("open", _params, socket) do
    {:noreply, assign(socket, :open, true)}
  end

  def handle_event("new_conversation", _params, socket) do
    AskAnythingStore.clear_messages(socket.assigns.current_user.id)
    {:noreply,
     socket
     |> assign(:active_tab, :chat)
     |> assign(:messages, [])
     |> assign(:current_conversation_id, nil)
     |> assign(:input_message, "")
     |> assign(:tagged_contact, nil)
     |> assign(:tagged_contact_id, nil)}
  end

  def handle_event("send_message", %{"message" => text}, socket) do
    trimmed = String.trim(text)
    if trimmed == "" do
      {:noreply, socket}
    else
      user = socket.assigns.current_user
      tagged_id = socket.assigns.tagged_contact_id
      provider = socket.assigns.crm_provider
      tagged_contact = socket.assigns.tagged_contact

      # Store content with " _" for display (contact inline); strip for AI
      text_for_ai = trimmed |> String.replace(" _", "") |> String.trim()
      created_at = DateTime.utc_now()
      user_msg = %{role: :user, content: trimmed, tagged_contact: tagged_contact, created_at: created_at}
      messages = socket.assigns.messages ++ [user_msg]
      AskAnythingStore.put_messages(user.id, messages)

      conv_id = get_or_create_conversation(socket.assigns.current_conversation_id, user.id)
      AskAnything.add_message(conv_id, user_msg)

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:current_conversation_id, conv_id)
        |> assign(:input_message, "")
        |> assign(:tagged_contact, nil)
        |> assign(:tagged_contact_id, nil)
        |> assign(:sending, true)

      send(self(), {:answer_question, text_for_ai, tagged_id, provider, user.id, tagged_contact})
      {:noreply, socket}
    end
  end

  def handle_event("update_input", %{"message" => value}, socket) do
    value = value || ""
    socket = assign(socket, input_message: value)
    socket =
      if socket.assigns.tagged_contact && !String.contains?(value, " _") do
        default_provider = default_crm_provider(socket.assigns.hubspot_credential, socket.assigns.salesforce_credential)
        socket
        |> assign(:tagged_contact, nil)
        |> assign(:tagged_contact_id, nil)
        |> assign(:crm_provider, default_provider)
      else
        socket
      end
    {:noreply, socket}
  end

  def handle_event("add_context_click", _params, socket) do
    {:noreply, assign(socket, contact_picker_open: true, contact_search_results: [])}
  end

  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)
    if String.length(query) >= 2 do
      send(self(), {:chat_contact_search, query, socket.assigns.hubspot_credential, socket.assigns.salesforce_credential})
      {:noreply, assign(socket, contact_search_query: query, contact_search_loading: true)}
    else
      {:noreply, assign(socket, contact_search_query: query, contact_search_results: [])}
    end
  end

  def handle_event("select_chat_contact", %{"id" => id, "provider" => provider}, socket) do
    results = socket.assigns.contact_search_results
    contact = Enum.find(results, fn c -> c.id == id and c.provider == provider end)
    if contact do
      new_input = (socket.assigns.input_message || "") <> " _"
      tagged = %{
        id: contact.id,
        name: contact.display_name,
        provider: provider,
        avatar_url: contact[:avatar_url]
      }
      {:noreply,
       socket
       |> assign(:tagged_contact, tagged)
       |> assign(:tagged_contact_id, contact.id)
       |> assign(:crm_provider, provider)
       |> assign(:input_message, new_input)
       |> assign(:contact_picker_open, false)
       |> assign(:contact_search_results, [])
       |> push_event("focus_ask_input", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_contact_picker", _params, socket) do
    {:noreply, assign(socket, contact_picker_open: false)}
  end

  def handle_event("clear_tagged_contact", _params, socket) do
    input = socket.assigns.input_message || ""
    new_input = trim_trailing_underscore(input)
    default_provider = default_crm_provider(socket.assigns.hubspot_credential, socket.assigns.salesforce_credential)
    {:noreply,
     socket
     |> assign(:tagged_contact, nil)
     |> assign(:tagged_contact_id, nil)
     |> assign(:crm_provider, default_provider)
     |> assign(:input_message, new_input)}
  end

  def handle_event("set_tab", %{"tab" => "history"}, socket) do
    messages = AskAnything.get_all_history_messages(socket.assigns.current_user.id)
    {:noreply,
     socket
     |> assign(:active_tab, :history)
     |> assign(:history_messages, messages)
     |> push_event("scroll_ask_to_bottom", %{})}
  end

  def handle_event("set_tab", %{"tab" => "chat"}, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, :chat)
     |> push_event("scroll_ask_to_bottom", %{})}
  end

  @impl true
  def handle_info({:answer_question, text, tagged_id, provider, user_id, tagged_contact}, socket) do
    result = CrmChat.answer_question(user_id, text, tagged_id, provider)

    socket =
      case result do
        {:ok, %{answer: answer, sources: sources}} ->
          created_at = DateTime.utc_now()
          msg = %{role: :ai, content: answer, sources: sources, tagged_contact: tagged_contact, created_at: created_at}
          messages = socket.assigns.messages ++ [msg]
          AskAnythingStore.put_messages(socket.assigns.current_user.id, messages)
          conv_id = socket.assigns.current_conversation_id
          if conv_id, do: AskAnything.add_message(conv_id, msg)
          socket |> assign(messages: messages, sending: false) |> push_event("scroll_ask_to_bottom", %{})

        {:error, reason} ->
          created_at = DateTime.utc_now()
          err_msg = %{role: :ai, content: "Sorry, I couldn't answer that. (#{inspect(reason)})", sources: [], tagged_contact: nil, created_at: created_at}
          messages = socket.assigns.messages ++ [err_msg]
          AskAnythingStore.put_messages(socket.assigns.current_user.id, messages)
          conv_id = socket.assigns.current_conversation_id
          if conv_id, do: AskAnything.add_message(conv_id, err_msg)
          socket |> assign(messages: messages, sending: false) |> push_event("scroll_ask_to_bottom", %{})
      end

    {:noreply, socket}
  end

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

  defp strip_inline_sources(content) when is_binary(content) do
    content
    |> String.replace(~r/\s*Sources:\s*[^\n]+/, "")
    |> String.trim()
  end

  defp strip_inline_sources(content), do: content

  defp user_message_parts(_content, nil), do: nil

  defp user_message_parts(content, tagged_contact) do
    parts = String.split(content, " _", parts: 2)
    case parts do
      [before, after_] -> {before, tagged_contact, after_}
      [_] -> nil
    end
  end

  defp trim_trailing_underscore(input) do
    input
    |> String.reverse()
    |> String.replace_leading(" _", "")
    |> String.reverse()
  end

  defp get_or_create_conversation(nil, user_id) do
    {:ok, conv} = AskAnything.create_conversation(user_id)
    conv.id
  end

  defp get_or_create_conversation(conv_id, _user_id) when is_integer(conv_id), do: conv_id

  defp show_message_timestamp?(_msg, nil), do: true

  defp show_message_timestamp?(msg, prev) do
    case {msg[:created_at], prev[:created_at]} do
      {nil, _} -> false
      {_, nil} -> true
      {a, b} -> format_timestamp(a) != format_timestamp(b)
    end
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
