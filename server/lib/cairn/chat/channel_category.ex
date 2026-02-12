defmodule Murmuring.Chat.ChannelCategory do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channel_categories" do
    field :name, :string
    field :position, :integer, default: 0

    belongs_to :server, Murmuring.Servers.Server
    has_many :channels, Murmuring.Chat.Channel, foreign_key: :category_id

    timestamps()
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :position, :server_id])
    |> validate_required([:name, :server_id])
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:server_id)
  end
end
