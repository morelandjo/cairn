defmodule Murmuring.Chat.LinkPreview do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "link_previews" do
    field :url_hash, :string
    field :url, :string
    field :title, :string
    field :description, :string
    field :image_url, :string
    field :site_name, :string
    field :expires_at, :utc_datetime

    timestamps()
  end

  def changeset(preview, attrs) do
    preview
    |> cast(attrs, [:url_hash, :url, :title, :description, :image_url, :site_name, :expires_at])
    |> validate_required([:url_hash, :url, :expires_at])
    |> unique_constraint([:url_hash])
  end
end
