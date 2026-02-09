defmodule SocialScribe.AskAnything.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Accounts.User
  alias SocialScribe.AskAnything.Message

  schema "ask_anything_conversations" do
    belongs_to :user, User

    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:user_id])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
  end
end
