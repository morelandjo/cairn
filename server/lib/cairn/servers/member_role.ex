defmodule Murmuring.Servers.MemberRole do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "server_member_roles" do
    belongs_to :server_member, Murmuring.Servers.ServerMember
    belongs_to :role, Murmuring.Accounts.Role

    timestamps()
  end

  def changeset(member_role, attrs) do
    member_role
    |> cast(attrs, [:server_member_id, :role_id])
    |> validate_required([:server_member_id, :role_id])
    |> foreign_key_constraint(:server_member_id)
    |> foreign_key_constraint(:role_id)
    |> unique_constraint([:server_member_id, :role_id])
  end
end
