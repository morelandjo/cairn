defmodule Murmuring.Moderation.ServerBan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "server_bans" do
    field :reason, :string
    field :expires_at, :utc_datetime

    belongs_to :server, Murmuring.Servers.Server
    belongs_to :user, Murmuring.Accounts.User
    belongs_to :banned_by, Murmuring.Accounts.User

    timestamps()
  end

  def changeset(ban, attrs) do
    ban
    |> cast(attrs, [:reason, :expires_at, :server_id, :user_id, :banned_by_id])
    |> validate_required([:server_id, :user_id, :banned_by_id])
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:banned_by_id)
    |> unique_constraint([:server_id, :user_id])
  end
end
