defmodule Murmuring.Moderation.ServerMute do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "server_mutes" do
    field :reason, :string
    field :expires_at, :utc_datetime

    belongs_to :server, Murmuring.Servers.Server
    belongs_to :user, Murmuring.Accounts.User
    belongs_to :channel, Murmuring.Chat.Channel
    belongs_to :muted_by, Murmuring.Accounts.User

    timestamps()
  end

  def changeset(mute, attrs) do
    mute
    |> cast(attrs, [:reason, :expires_at, :server_id, :user_id, :channel_id, :muted_by_id])
    |> validate_required([:server_id, :user_id, :muted_by_id])
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:channel_id)
    |> foreign_key_constraint(:muted_by_id)
  end
end
