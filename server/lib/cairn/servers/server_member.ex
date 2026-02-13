defmodule Cairn.Servers.ServerMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "server_members" do
    belongs_to :server, Cairn.Servers.Server
    belongs_to :user, Cairn.Accounts.User
    belongs_to :role, Cairn.Accounts.Role

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:server_id, :user_id, :role_id])
    |> validate_required([:server_id, :user_id])
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:role_id)
    |> unique_constraint([:server_id, :user_id])
  end
end
