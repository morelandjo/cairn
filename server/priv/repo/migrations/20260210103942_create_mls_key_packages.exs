defmodule Murmuring.Repo.Migrations.CreateMlsKeyPackages do
  use Ecto.Migration

  def change do
    create table(:mls_key_packages, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :data, :binary, null: false
      add :consumed, :boolean, default: false, null: false

      timestamps()
    end

    create index(:mls_key_packages, [:user_id, :consumed])
  end
end
