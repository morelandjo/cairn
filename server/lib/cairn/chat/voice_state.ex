defmodule Murmuring.Chat.VoiceState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "voice_states" do
    field :muted, :boolean, default: false
    field :deafened, :boolean, default: false
    field :video_on, :boolean, default: false
    field :screen_sharing, :boolean, default: false
    field :joined_at, :utc_datetime

    belongs_to :channel, Murmuring.Chat.Channel
    belongs_to :user, Murmuring.Accounts.User
    belongs_to :server, Murmuring.Servers.Server

    timestamps()
  end

  def changeset(voice_state, attrs) do
    voice_state
    |> cast(attrs, [
      :channel_id,
      :user_id,
      :server_id,
      :muted,
      :deafened,
      :video_on,
      :screen_sharing,
      :joined_at
    ])
    |> validate_required([:channel_id, :user_id, :joined_at])
    |> unique_constraint([:channel_id, :user_id])
  end

  def update_changeset(voice_state, attrs) do
    voice_state
    |> cast(attrs, [:muted, :deafened, :video_on, :screen_sharing])
  end
end
