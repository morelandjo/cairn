defmodule Murmuring.Accounts.Role do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "roles" do
    field :name, :string
    field :permissions, :map, default: %{}
    field :priority, :integer, default: 0
    field :color, :string

    belongs_to :server, Murmuring.Servers.Server

    timestamps()
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :permissions, :priority, :color, :server_id])
    |> validate_required([:name])
    |> validate_length(:name, max: 64)
    |> unique_constraint([:server_id, :name])
  end
end
