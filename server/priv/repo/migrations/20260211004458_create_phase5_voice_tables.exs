defmodule Cairn.Repo.Migrations.CreatePhase5VoiceTables do
  use Ecto.Migration

  def change do
    create table(:voice_states, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all)
      add :muted, :boolean, default: false
      add :deafened, :boolean, default: false
      add :video_on, :boolean, default: false
      add :screen_sharing, :boolean, default: false
      add :joined_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:voice_states, [:channel_id, :user_id])
    create index(:voice_states, [:user_id])
    create index(:voice_states, [:server_id])

    alter table(:channels) do
      add :max_participants, :integer, default: 25
      add :bitrate, :integer, default: 64000
    end
  end
end
