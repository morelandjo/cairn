defmodule Cairn.Storage.FileRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "files" do
    field :storage_key, :string
    field :original_name, :string
    field :content_type, :string
    field :size_bytes, :integer
    field :thumbnail_key, :string

    belongs_to :uploader, Cairn.Accounts.User

    timestamps()
  end

  def changeset(file_record, attrs) do
    file_record
    |> cast(attrs, [
      :storage_key,
      :original_name,
      :content_type,
      :size_bytes,
      :uploader_id,
      :thumbnail_key
    ])
    |> validate_required([:storage_key, :original_name, :content_type, :size_bytes])
    |> validate_number(:size_bytes, greater_than: 0, less_than_or_equal_to: 25 * 1024 * 1024)
  end
end
