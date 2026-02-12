defmodule Murmuring.Auth.RefreshToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "refresh_tokens" do
    field :token_hash, :string
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, Murmuring.Accounts.User

    timestamps()
  end

  def changeset(refresh_token, attrs) do
    refresh_token
    |> cast(attrs, [:token_hash, :user_id, :expires_at, :revoked_at])
    |> validate_required([:token_hash, :user_id, :expires_at])
    |> unique_constraint(:token_hash)
  end

  def revoke_changeset(refresh_token) do
    change(refresh_token, revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
