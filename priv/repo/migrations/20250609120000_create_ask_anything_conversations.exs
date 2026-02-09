defmodule SocialScribe.Repo.Migrations.CreateAskAnythingConversations do
  use Ecto.Migration

  def change do
    create table(:ask_anything_conversations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:ask_anything_conversations, [:user_id])

    create table(:ask_anything_messages) do
      add :conversation_id, references(:ask_anything_conversations, on_delete: :delete_all),
        null: false

      add :role, :string, null: false
      add :content, :text, null: false
      add :sources, {:array, :string}, default: []
      add :tagged_contact, :map
      add :message_created_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:ask_anything_messages, [:conversation_id])
  end
end
