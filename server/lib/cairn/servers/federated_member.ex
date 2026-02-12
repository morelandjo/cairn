defmodule Murmuring.Servers.FederatedMember do
  @moduledoc """
  Schema for federated user membership in a local server.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "federated_members" do
    belongs_to :server, Murmuring.Servers.Server
    belongs_to :federated_user, Murmuring.Federation.FederatedUser
    belongs_to :role, Murmuring.Accounts.Role

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:server_id, :federated_user_id, :role_id])
    |> validate_required([:server_id, :federated_user_id])
    |> unique_constraint([:server_id, :federated_user_id])
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:federated_user_id)
  end
end
