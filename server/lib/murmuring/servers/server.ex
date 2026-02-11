defmodule Murmuring.Servers.Server do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "servers" do
    field :name, :string
    field :description, :string
    field :icon_key, :string

    belongs_to :creator, Murmuring.Accounts.User
    has_many :channels, Murmuring.Chat.Channel
    has_many :roles, Murmuring.Accounts.Role
    has_many :server_members, Murmuring.Servers.ServerMember
    has_many :invite_links, Murmuring.Accounts.InviteLink

    timestamps()
  end

  def changeset(server, attrs) do
    server
    |> cast(attrs, [:name, :description, :icon_key, :creator_id])
    |> validate_required([:name, :creator_id])
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:creator_id)
  end
end
