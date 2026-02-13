defmodule Cairn.Notifications.Preference do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_levels ~w(all mentions nothing)

  schema "notification_preferences" do
    field :level, :string, default: "all"
    field :dnd_enabled, :boolean, default: false
    field :quiet_hours_start, :time
    field :quiet_hours_end, :time

    belongs_to :user, Cairn.Accounts.User
    belongs_to :server, Cairn.Servers.Server
    belongs_to :channel, Cairn.Chat.Channel

    timestamps()
  end

  def changeset(pref, attrs) do
    pref
    |> cast(attrs, [
      :level,
      :dnd_enabled,
      :quiet_hours_start,
      :quiet_hours_end,
      :user_id,
      :server_id,
      :channel_id
    ])
    |> validate_required([:user_id, :level])
    |> validate_inclusion(:level, @valid_levels)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:channel_id)
    |> unique_constraint([:user_id, :server_id, :channel_id])
  end
end
