defmodule SocialScribe.AskAnything do
  @moduledoc """
  Context for Ask Anything chat history persistence.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo

  alias SocialScribe.AskAnything.{Conversation, Message}

  @doc """
  Gets the user's most recent conversation and its messages.
  Returns {conversation_id, messages} or {nil, []} if none.
  Message format: %{role: :user | :ai, content: ..., tagged_contact: ..., sources: [...], created_at: ...}
  """
  def get_latest_conversation(user_id) do
    from(c in Conversation,
      where: c.user_id == ^user_id,
      order_by: [desc: c.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> {nil, []}
      conv -> {conv.id, conversation_to_messages(conv)}
    end
  end

  @doc """
  Gets ALL messages from ALL conversations for a user, ordered by created_at.
  Returns list of message maps in sidebar format (same as get_conversation_messages).
  """
  def get_all_history_messages(user_id) do
    from(m in Message,
      join: c in assoc(m, :conversation),
      where: c.user_id == ^user_id,
      order_by: [asc: m.message_created_at]
    )
    |> Repo.all()
    |> Enum.map(fn m ->
      role = if m.role == "user", do: :user, else: :ai
      tagged = atomize_map(m.tagged_contact)

      %{
        role: role,
        content: m.content,
        tagged_contact: tagged,
        sources: m.sources || [],
        created_at: m.message_created_at
      }
    end)
  end

  @doc """
  Lists all conversations for a user, most recent first.
  Returns list of %{id: id, inserted_at: datetime, first_message_preview: string}.
  """
  def list_user_conversations(user_id) do
    from(c in Conversation,
      where: c.user_id == ^user_id,
      order_by: [desc: c.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn conv ->
      conv = Repo.preload(conv, messages: from(m in Message, order_by: [asc: m.id], limit: 1))
      first = List.first(conv.messages || [])
      preview = if first, do: truncate_preview(first.content, 60), else: ""

      %{
        id: conv.id,
        inserted_at: conv.inserted_at,
        first_message_preview: preview
      }
    end)
  end

  @doc """
  Gets messages for a specific conversation.
  Returns list of message maps in sidebar format.
  """
  def get_conversation_messages(conversation_id) do
    from(c in Conversation, where: c.id == ^conversation_id)
    |> Repo.one()
    |> case do
      nil -> []
      conv -> conversation_to_messages(conv)
    end
  end

  defp truncate_preview(text, max_len) when byte_size(text) <= max_len, do: text
  defp truncate_preview(text, max_len), do: String.slice(text, 0, max_len) <> "…"

  @doc """
  Creates a new conversation for the user and returns it.
  """
  def create_conversation(user_id) do
    %Conversation{}
    |> Conversation.changeset(%{user_id: user_id})
    |> Repo.insert()
  end

  @doc """
  Appends a message to a conversation. The message map should have:
  - role: :user | :ai (will be converted to string)
  - content: string
  - tagged_contact: map | nil
  - sources: list (for AI messages)
  - created_at: DateTime
  """
  def add_message(conversation_id, msg) do
    attrs = %{
      conversation_id: conversation_id,
      role: to_string(msg.role),
      content: msg.content,
      sources: msg[:sources] || [],
      tagged_contact: msg[:tagged_contact],
      message_created_at: msg.created_at
    }

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  defp conversation_to_messages(conversation) do
    conversation =
      Repo.preload(conversation, messages: from(m in Message, order_by: [asc: m.id]))

    conversation.messages
    |> Enum.map(fn m ->
      role = if m.role == "user", do: :user, else: :ai
      tagged = atomize_map(m.tagged_contact)

      %{
        role: role,
        content: m.content,
        tagged_contact: tagged,
        sources: m.sources || [],
        created_at: m.message_created_at
      }
    end)
  end

  defp atomize_map(nil), do: nil

  defp atomize_map(%{} = map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} -> {k, v}
    end)
  end
end
