defmodule Cairn.Keys.MlsKeyPackage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mls_key_packages" do
    field :data, :binary
    field :consumed, :boolean, default: false
    belongs_to :user, Cairn.Accounts.User

    timestamps()
  end

  def changeset(key_package, attrs) do
    key_package
    |> cast(attrs, [:data, :user_id, :consumed])
    |> validate_required([:data, :user_id])
  end
end
