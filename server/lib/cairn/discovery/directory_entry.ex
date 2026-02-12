defmodule Cairn.Discovery.DirectoryEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "server_directory_entries" do
    field :description, :string
    field :tags, {:array, :string}, default: []
    field :member_count, :integer, default: 0
    field :listed_at, :utc_datetime

    belongs_to :server, Cairn.Servers.Server

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:description, :tags, :member_count, :server_id, :listed_at])
    |> validate_required([:server_id])
    |> validate_length(:description, max: 500)
    |> validate_length(:tags, max: 10)
    |> foreign_key_constraint(:server_id)
    |> unique_constraint([:server_id])
  end
end
