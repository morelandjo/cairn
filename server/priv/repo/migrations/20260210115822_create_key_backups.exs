defmodule Cairn.Repo.Migrations.CreateKeyBackups do
  use Ecto.Migration

  def change do
    create table(:key_backups, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :data, :binary, null: false
      add :size_bytes, :integer, null: false

      timestamps()
    end

    create unique_index(:key_backups, [:user_id])
  end
end
