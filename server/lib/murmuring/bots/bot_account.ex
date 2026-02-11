defmodule Murmuring.Bots.BotAccount do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bot_accounts" do
    field :api_token_hash, :string
    field :allowed_channels, {:array, :binary_id}, default: []

    belongs_to :user, Murmuring.Accounts.User
    belongs_to :server, Murmuring.Servers.Server
    belongs_to :creator, Murmuring.Accounts.User

    timestamps()
  end

  def changeset(bot, attrs) do
    bot
    |> cast(attrs, [:api_token_hash, :allowed_channels, :user_id, :server_id, :creator_id])
    |> validate_required([:api_token_hash, :user_id, :server_id, :creator_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:creator_id)
    |> unique_constraint([:user_id, :server_id])
  end

  def generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  def hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
