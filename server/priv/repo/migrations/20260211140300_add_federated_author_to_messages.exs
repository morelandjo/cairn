defmodule Cairn.Repo.Migrations.AddFederatedAuthorToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :federated_author_id,
          references(:federated_users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:messages, [:federated_author_id])
  end
end
