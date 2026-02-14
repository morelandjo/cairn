defmodule Cairn.Repo.Migrations.AddSecureToFederatedNodes do
  use Ecto.Migration

  def change do
    alter table(:federated_nodes) do
      add :secure, :boolean, default: true, null: false
    end
  end
end
