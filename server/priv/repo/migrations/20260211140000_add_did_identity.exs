defmodule Cairn.Repo.Migrations.AddDidIdentity do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :did, :string
      add :rotation_public_key, :binary
    end

    create unique_index(:users, [:did])

    create table(:did_operations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :did, :string, null: false
      add :seq, :integer, null: false
      add :operation_type, :string, null: false
      add :payload, :map, null: false
      add :signature, :binary, null: false
      add :prev_hash, :string
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:did_operations, [:did, :seq])
    create index(:did_operations, [:user_id])
  end
end
