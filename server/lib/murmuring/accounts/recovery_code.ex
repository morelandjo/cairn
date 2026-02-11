defmodule Murmuring.Accounts.RecoveryCode do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "recovery_codes" do
    field :code_hash, :string
    field :used_at, :utc_datetime

    belongs_to :user, Murmuring.Accounts.User

    timestamps()
  end

  def changeset(recovery_code, attrs) do
    recovery_code
    |> cast(attrs, [:code_hash, :user_id, :used_at])
    |> validate_required([:code_hash, :user_id])
  end
end
