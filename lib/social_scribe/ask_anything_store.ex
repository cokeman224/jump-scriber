defmodule SocialScribe.AskAnythingStore do
  @moduledoc """
  In-memory store for Ask Anything chat history per user.
  Persists across sidebar close/reopen and page navigation.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get_messages(user_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state, user_id, [])
    end)
  end

  def put_messages(user_id, messages) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, user_id, messages)
    end)
  end

  def append_message(user_id, message) do
    Agent.update(__MODULE__, fn state ->
      current = Map.get(state, user_id, [])
      Map.put(state, user_id, current ++ [message])
    end)
  end

  def clear_messages(user_id) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, user_id, [])
    end)
  end
end
