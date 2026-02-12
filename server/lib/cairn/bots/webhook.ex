defmodule Murmuring.Bots.Webhook do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "webhooks" do
    field :name, :string
    field :token, :string
    field :avatar_key, :string

    belongs_to :server, Murmuring.Servers.Server
    belongs_to :channel, Murmuring.Chat.Channel
    belongs_to :creator, Murmuring.Accounts.User

    timestamps()
  end

  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:name, :token, :avatar_key, :server_id, :channel_id, :creator_id])
    |> validate_required([:name, :token, :server_id, :channel_id, :creator_id])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint([:token])
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:channel_id)
    |> foreign_key_constraint(:creator_id)
  end

  def generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
