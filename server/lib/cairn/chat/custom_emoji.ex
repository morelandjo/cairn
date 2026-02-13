defmodule Cairn.Chat.CustomEmoji do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "custom_emojis" do
    field :name, :string
    field :file_key, :string
    field :animated, :boolean, default: false

    belongs_to :server, Cairn.Servers.Server
    belongs_to :uploader, Cairn.Accounts.User

    timestamps()
  end

  def changeset(emoji, attrs) do
    emoji
    |> cast(attrs, [:name, :file_key, :animated, :server_id, :uploader_id])
    |> validate_required([:name, :file_key, :server_id, :uploader_id])
    |> validate_length(:name, min: 2, max: 32)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_]+$/,
      message: "must be alphanumeric with underscores"
    )
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:uploader_id)
    |> unique_constraint([:server_id, :name])
  end
end
