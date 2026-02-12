defmodule Cairn.Repo.Migrations.AddFederatedDmSupport do
  use Ecto.Migration

  def change do
    # Allow federated users to be channel members (for cross-instance DMs)
    alter table(:channel_members) do
      add :federated_user_id,
          references(:federated_users, type: :binary_id, on_delete: :delete_all)
    end

    create index(:channel_members, [:federated_user_id])

    # A channel_member has either user_id OR federated_user_id, not both.
    # We make user_id nullable now (was required before).
    # The application-level changeset enforces mutual exclusion.
    execute(
      "ALTER TABLE channel_members ALTER COLUMN user_id DROP NOT NULL",
      "ALTER TABLE channel_members ALTER COLUMN user_id SET NOT NULL"
    )

    # Unique index for federated user per channel (like the existing user_id one)
    create unique_index(:channel_members, [:channel_id, :federated_user_id],
             where: "federated_user_id IS NOT NULL",
             name: :channel_members_channel_id_federated_user_id_index
           )

    # DM request tracking for consent/anti-spam
    create table(:dm_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all), null: false
      add :sender_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :recipient_did, :string, null: false
      add :recipient_instance, :string, null: false
      add :status, :string, null: false, default: "pending"

      timestamps()
    end

    create unique_index(:dm_requests, [:sender_id, :recipient_did])
    create index(:dm_requests, [:recipient_did])
    create index(:dm_requests, [:status])

    # DM block list (DID-based)
    create table(:dm_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :blocked_did, :string, null: false

      timestamps()
    end

    create unique_index(:dm_blocks, [:user_id, :blocked_did])
    create index(:dm_blocks, [:blocked_did])
  end
end
