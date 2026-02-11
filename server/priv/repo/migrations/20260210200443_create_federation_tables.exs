defmodule Murmuring.Repo.Migrations.CreateFederationTables do
  use Ecto.Migration

  def change do
    # Federated nodes — remote instances we know about
    create table(:federated_nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :domain, :string, null: false
      add :node_id, :string, null: false
      add :public_key, :text, null: false
      add :inbox_url, :string, null: false
      add :protocol_version, :string, null: false
      add :privacy_manifest, :map, default: %{}
      add :status, :string, null: false, default: "pending"

      timestamps()
    end

    create unique_index(:federated_nodes, [:domain])
    create unique_index(:federated_nodes, [:node_id])

    # Federation activities — audit trail for inbound/outbound AP activities
    create table(:federation_activities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :federated_node_id,
          references(:federated_nodes, type: :binary_id, on_delete: :delete_all), null: false

      add :activity_type, :string, null: false
      add :direction, :string, null: false
      add :actor_uri, :string
      add :object_uri, :string
      add :payload, :map, default: %{}
      add :status, :string, null: false, default: "pending"
      add :error, :text

      timestamps()
    end

    create index(:federation_activities, [:federated_node_id])
    create index(:federation_activities, [:activity_type])
    create index(:federation_activities, [:direction])
    create index(:federation_activities, [:inserted_at])
  end
end
