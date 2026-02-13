defmodule Cairn.Moderation.ModLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "moderation_log" do
    field :action, :string
    field :details, :map, default: %{}

    belongs_to :server, Cairn.Servers.Server
    belongs_to :moderator, Cairn.Accounts.User
    belongs_to :target_user, Cairn.Accounts.User
    belongs_to :target_message, Cairn.Chat.Message
    belongs_to :target_channel, Cairn.Chat.Channel

    timestamps()
  end

  @valid_actions ~w(mute unmute kick ban unban delete_message pin_message report auto_mod)

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :action,
      :details,
      :server_id,
      :moderator_id,
      :target_user_id,
      :target_message_id,
      :target_channel_id
    ])
    |> validate_required([:action, :server_id, :moderator_id])
    |> validate_inclusion(:action, @valid_actions)
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:moderator_id)
  end
end
