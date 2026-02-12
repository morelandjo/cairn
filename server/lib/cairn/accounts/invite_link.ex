defmodule Murmuring.Accounts.InviteLink do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invite_links" do
    field :code, :string
    field :max_uses, :integer
    field :uses, :integer, default: 0
    field :expires_at, :utc_datetime

    belongs_to :creator, Murmuring.Accounts.User
    belongs_to :channel, Murmuring.Chat.Channel
    belongs_to :server, Murmuring.Servers.Server

    timestamps()
  end

  def changeset(invite_link, attrs) do
    invite_link
    |> cast(attrs, [:code, :creator_id, :channel_id, :server_id, :max_uses, :expires_at])
    |> validate_required([:code, :creator_id])
    |> validate_channel_or_server()
    |> validate_length(:code, is: 8)
    |> unique_constraint(:code)
  end

  defp validate_channel_or_server(changeset) do
    channel_id = get_field(changeset, :channel_id)
    server_id = get_field(changeset, :server_id)

    if is_nil(channel_id) and is_nil(server_id) do
      add_error(changeset, :channel_id, "either channel_id or server_id is required")
    else
      changeset
    end
  end

  def generate_code do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false) |> String.slice(0, 8)
  end
end
