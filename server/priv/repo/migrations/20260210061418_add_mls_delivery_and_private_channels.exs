defmodule Murmuring.Repo.Migrations.AddMlsDeliveryAndPrivateChannels do
  use Ecto.Migration

  def change do
    # MLS protocol messages (opaque blobs relayed by untrusted server)
    create table(:mls_messages, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :channel_id, references(:channels, type: :uuid, on_delete: :delete_all), null: false

      add :sender_id, references(:users, type: :uuid, on_delete: :nilify_all), null: false

      add :recipient_id, references(:users, type: :uuid, on_delete: :delete_all)

      add :message_type, :string, size: 16, null: false
      add :data, :binary, null: false
      add :epoch, :bigint
      add :processed, :boolean, default: false, null: false

      timestamps()
    end

    create index(:mls_messages, [:channel_id, :inserted_at])
    create index(:mls_messages, [:recipient_id, :processed])

    # MLS group info (one per private channel, latest state)
    create table(:mls_group_info, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :channel_id, references(:channels, type: :uuid, on_delete: :delete_all), null: false

      add :data, :binary, null: false
      add :epoch, :bigint, null: false

      timestamps()
    end

    create unique_index(:mls_group_info, [:channel_id])

    # Add mls_epoch to messages table for E2EE message ordering
    alter table(:messages) do
      add :mls_epoch, :bigint
    end
  end
end
