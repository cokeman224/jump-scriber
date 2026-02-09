defmodule SocialScribe.AskAnything.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.AskAnything.Conversation

  schema "ask_anything_messages" do
    field :role, :string
    field :content, :string
    field :sources, {:array, :string}
    field :tagged_contact, :map
    field :message_created_at, :utc_datetime

    belongs_to :conversation, Conversation

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :role, :content, :sources, :tagged_contact, :message_created_at])
    |> validate_required([:conversation_id, :role, :content, :message_created_at])
    |> foreign_key_constraint(:conversation_id)
  end
end
