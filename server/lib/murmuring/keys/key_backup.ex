defmodule Murmuring.Keys.KeyBackup do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_backup_size 10 * 1024 * 1024

  schema "key_backups" do
    field :data, :binary
    field :size_bytes, :integer

    belongs_to :user, Murmuring.Accounts.User

    timestamps()
  end

  def changeset(backup, attrs) do
    backup
    |> cast(attrs, [:user_id, :data, :size_bytes])
    |> validate_required([:user_id, :data, :size_bytes])
    |> validate_number(:size_bytes, greater_than: 0, less_than_or_equal_to: @max_backup_size)
    |> unique_constraint(:user_id)
  end
end
