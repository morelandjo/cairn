defmodule Murmuring.Keys.OneTimePrekey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "one_time_prekeys" do
    field :key_id, :integer
    field :public_key, :binary
    field :consumed, :boolean, default: false

    belongs_to :user, Murmuring.Accounts.User

    timestamps()
  end

  def changeset(prekey, attrs) do
    prekey
    |> cast(attrs, [:key_id, :public_key, :user_id, :consumed])
    |> validate_required([:key_id, :public_key, :user_id])
    |> unique_constraint([:user_id, :key_id])
  end
end
