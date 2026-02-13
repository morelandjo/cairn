defmodule Cairn.Repo.Migrations.CreateFederatedMembers do
  use Ecto.Migration

  def change do
    create table(:federated_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false

      add :federated_user_id,
          references(:federated_users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role_id, references(:roles, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:federated_members, [:server_id, :federated_user_id])
    create index(:federated_members, [:federated_user_id])
  end
end
