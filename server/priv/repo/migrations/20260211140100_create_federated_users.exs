defmodule Cairn.Repo.Migrations.CreateFederatedUsers do
  use Ecto.Migration

  def change do
    create table(:federated_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :did, :string, null: false
      add :username, :string, null: false
      add :display_name, :string
      add :home_instance, :string, null: false
      add :public_key, :binary, null: false
      add :avatar_url, :string
      add :actor_uri, :string, null: false
      add :last_synced_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:federated_users, [:did])
    create unique_index(:federated_users, [:actor_uri])
    create index(:federated_users, [:home_instance])
  end
end
