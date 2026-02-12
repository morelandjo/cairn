defmodule Cairn.Repo.Migrations.AddHlcToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :hlc_wall, :bigint
      add :hlc_counter, :integer, default: 0
      add :hlc_node, :string
    end

    create index(:messages, [:hlc_wall, :hlc_counter])
  end
end
