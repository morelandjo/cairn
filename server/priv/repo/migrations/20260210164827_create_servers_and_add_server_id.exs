defmodule Murmuring.Repo.Migrations.CreateServersAndAddServerId do
  use Ecto.Migration

  def change do
    create table(:servers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, size: 100, null: false
      add :description, :text
      add :icon_key, :string
      add :creator_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps()
    end

    create index(:servers, [:creator_id])

    create table(:server_members, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :server_id, references(:servers, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :role_id, references(:roles, type: :uuid, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:server_members, [:server_id, :user_id])
    create index(:server_members, [:user_id])

    # Add nullable server_id to channels, roles, invite_links
    alter table(:channels) do
      add :server_id, references(:servers, type: :uuid, on_delete: :delete_all)
    end

    create index(:channels, [:server_id])

    alter table(:roles) do
      add :server_id, references(:servers, type: :uuid, on_delete: :delete_all)
    end

    create index(:roles, [:server_id])

    # Drop the old unique index on roles name and create per-server unique index
    drop unique_index(:roles, [:name])
    create unique_index(:roles, [:server_id, :name])

    alter table(:invite_links) do
      add :server_id, references(:servers, type: :uuid, on_delete: :delete_all)
    end

    create index(:invite_links, [:server_id])
  end
end
