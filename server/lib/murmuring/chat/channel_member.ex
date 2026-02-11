defmodule Murmuring.Chat.ChannelMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channel_members" do
    field :role, :string, default: "member"

    belongs_to :channel, Murmuring.Chat.Channel
    belongs_to :user, Murmuring.Accounts.User
    belongs_to :federated_user, Murmuring.Federation.FederatedUser

    timestamps()
  end

  @doc "Changeset for local user channel membership."
  def changeset(channel_member, attrs) do
    channel_member
    |> cast(attrs, [:channel_id, :user_id, :role])
    |> validate_required([:channel_id, :user_id, :role])
    |> validate_inclusion(:role, ~w(owner moderator member))
    |> unique_constraint([:channel_id, :user_id])
  end

  @doc "Changeset for federated user channel membership (cross-instance DMs)."
  def federated_changeset(channel_member, attrs) do
    channel_member
    |> cast(attrs, [:channel_id, :federated_user_id, :role])
    |> validate_required([:channel_id, :federated_user_id, :role])
    |> validate_inclusion(:role, ~w(owner moderator member))
    |> unique_constraint([:channel_id, :federated_user_id])
  end
end
