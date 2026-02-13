defmodule Cairn.Repo.Migrations.CreatePushTokens do
  use Ecto.Migration

  def change do
    create table(:push_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :platform, :string, null: false
      add :device_id, :string

      timestamps()
    end

    create unique_index(:push_tokens, [:token])
    create index(:push_tokens, [:user_id])
  end
end
