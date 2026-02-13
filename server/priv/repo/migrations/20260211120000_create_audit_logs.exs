defmodule Cairn.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :target_id, :string
      add :target_type, :string
      add :metadata, :map, default: %{}
      add :ip_address, :string
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
    end

    create index(:audit_logs, [:event_type])
    create index(:audit_logs, [:actor_id])
    create index(:audit_logs, [:inserted_at])
  end
end
