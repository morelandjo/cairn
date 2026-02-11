defmodule Murmuring.Repo.Migrations.AddHistoryAccessibleToChannels do
  use Ecto.Migration

  def change do
    alter table(:channels) do
      add :history_accessible, :boolean, default: false, null: false
    end
  end
end
