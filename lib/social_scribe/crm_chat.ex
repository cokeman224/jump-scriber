defmodule SocialScribe.CrmChat do
  @moduledoc """
  Answers user questions using CRM data (HubSpot or Salesforce) and meeting transcripts.
  """

  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApi
  alias SocialScribe.SalesforceApi
  alias SocialScribe.Meetings
  alias SocialScribe.AIContentGenerator

  require Logger

  @doc """
  Answers a question using the user's CRM and meeting data.

  - user_id: current user id
  - message: the user's question
  - tagged_contact_id: optional contact id from CRM (from HubSpot or Salesforce)
  - crm_provider: "hubspot" or "salesforce" (optional; uses whichever is connected if one)

  Returns {:ok, %{answer: String.t(), sources: list(String.t())}} or {:error, reason}.
  """
  def answer_question(user_id, message, tagged_contact_id \\ nil, crm_provider \\ nil) do
    credential = get_crm_credential(user_id, crm_provider)

    if is_nil(credential) do
      {:error, :no_crm_connected}
    else
      contact_info = fetch_contact_info(credential, tagged_contact_id)
      meeting_context = fetch_meeting_context(user_id, contact_info)
      prompt = build_prompt(message, contact_info, meeting_context)
      call_gemini_and_parse(prompt, credential, contact_info, meeting_context)
    end
  end

  defp get_crm_credential(user_id, nil) do
    Accounts.get_user_hubspot_credential(user_id) ||
      Accounts.get_user_salesforce_credential(user_id)
  end

  defp get_crm_credential(user_id, "hubspot"), do: Accounts.get_user_hubspot_credential(user_id)
  defp get_crm_credential(user_id, "salesforce"), do: Accounts.get_user_salesforce_credential(user_id)
  defp get_crm_credential(_, _), do: nil

  defp fetch_contact_info(_credential, nil), do: nil

  defp fetch_contact_info(%{provider: "hubspot"} = cred, contact_id) do
    case HubspotApi.get_contact(cred, contact_id) do
      {:ok, c} -> %{provider: "HubSpot", name: c.display_name, details: c}
      _ -> nil
    end
  end

  defp fetch_contact_info(%{provider: "salesforce"} = cred, contact_id) do
    case SalesforceApi.get_contact(cred, contact_id) do
      {:ok, c} -> %{provider: "Salesforce", name: c.display_name, details: c}
      _ -> nil
    end
  end

  defp fetch_meeting_context(user_id, contact_info) do
    user = Accounts.get_user!(user_id)
    meetings =
      Meetings.list_user_meetings(user)
      |> Enum.take(10)

    # If we have a tagged contact, prefer meetings where they might appear (by name/email)
    filter_fn =
      if contact_info && contact_info[:name] do
        name_lower = String.downcase(contact_info[:name])
        fn m ->
          transcript = m.meeting_transcript && m.meeting_transcript.content && m.meeting_transcript.content["data"]
          if is_list(transcript) do
            text = transcript |> Enum.map_join(" ", fn s -> (s["words"] || []) |> Enum.map_join(" ", & &1["text"]) end)
            String.contains?(String.downcase(text || ""), name_lower)
          else
            true
          end
        end
      else
        fn _ -> true end
      end

    meetings
    |> Enum.filter(filter_fn)
    |> Enum.take(5)
    |> Enum.map(fn m ->
      case Meetings.generate_prompt_for_meeting(m) do
        {:ok, prompt} -> %{title: m.title, date: m.recorded_at, prompt: prompt}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_prompt(message, contact_info, meeting_context) do
    contact_section =
      if contact_info do
        """
        ## Tagged contact (#{contact_info.provider}):
        Name: #{contact_info[:name]}
        Details: #{inspect(contact_info.details)}
        """
      else
        ""
      end

    meetings_section =
      if Enum.any?(meeting_context) do
        "## Relevant meeting excerpts:\n" <>
          (meeting_context
           |> Enum.map(fn ctx -> "### #{ctx.title} (#{ctx.date})\n#{ctx.prompt}\n" end)
           |> Enum.join("\n"))
      else
        "## No specific meeting context provided.\n"
      end

    """
    You are an assistant that answers questions about the user's meetings and CRM data.
    Use only the information provided below. If the answer is not in the context, say so.

    #{contact_section}
    #{meetings_section}

    User question: #{message}

    Provide a concise answer. At the end, list sources in one line, e.g. "Sources: Contact from Salesforce; Meeting on Nov 3, 2025."
    """
  end

  defp call_gemini_and_parse(prompt, _credential, contact_info, meeting_context) do
    api_key = Application.get_env(:social_scribe, :gemini_api_key)
    if is_nil(api_key) or api_key == "" do
      {:error, {:config_error, "GEMINI_API_KEY not set"}}
    else
      path = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=#{api_key}"
      payload = %{contents: [%{parts: [%{text: prompt}]}]}
      client = Tesla.client([Tesla.Middleware.JSON])

      case Tesla.post(client, path, payload) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          text = get_in(body, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
          answer = text || "No response."
          sources = build_sources_list(contact_info, meeting_context)
          {:ok, %{answer: answer, sources: sources}}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end
  end

  defp build_sources_list(contact_info, meeting_context) do
    sources = []
    sources = if contact_info, do: ["Contact from #{contact_info.provider}" | sources], else: sources
    sources =
      meeting_context
      |> Enum.map(fn ctx -> "Meeting: #{ctx.title} (#{ctx.date})" end)
      |> Enum.reverse()
      |> Enum.concat(sources)
      |> Enum.uniq()

    if Enum.empty?(sources), do: ["General knowledge"], else: sources
  end
end
