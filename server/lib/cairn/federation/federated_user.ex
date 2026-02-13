defmodule Cairn.Federation.FederatedUser do
  @moduledoc """
  Schema for cached remote (federated) user profiles.

  These are users whose home instance is elsewhere. We cache their
  profile data, DID, and public key for display and verification.
  The home instance is authoritative — this is a cache.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "federated_users" do
    field :did, :string
    field :username, :string
    field :display_name, :string
    field :home_instance, :string
    field :public_key, :binary
    field :avatar_url, :string
    field :actor_uri, :string
    field :last_synced_at, :utc_datetime_usec

    timestamps()
  end

  def changeset(federated_user, attrs) do
    federated_user
    |> cast(attrs, [
      :did,
      :username,
      :display_name,
      :home_instance,
      :public_key,
      :avatar_url,
      :actor_uri,
      :last_synced_at
    ])
    |> validate_required([:did, :username, :home_instance, :public_key, :actor_uri])
    |> unique_constraint(:did)
    |> unique_constraint(:actor_uri)
  end
end
