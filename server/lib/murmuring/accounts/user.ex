defmodule Murmuring.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :username, :string
    field :display_name, :string
    field :password_hash, :string
    field :identity_public_key, :binary
    field :signed_prekey, :binary
    field :signed_prekey_signature, :binary
    field :totp_secret, :binary
    field :is_bot, :boolean, default: false
    field :did, :string
    field :rotation_public_key, :binary

    field :password, :string, virtual: true, redact: true

    has_many :recovery_codes, Murmuring.Accounts.RecoveryCode
    has_many :channel_members, Murmuring.Chat.ChannelMember
    has_many :refresh_tokens, Murmuring.Auth.RefreshToken
    has_many :did_operations, Murmuring.Identity.Operation

    timestamps()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :display_name, :password])
    |> validate_username()
    |> validate_password()
  end

  def key_changeset(user, attrs) do
    user
    |> cast(attrs, [:identity_public_key, :signed_prekey, :signed_prekey_signature])
    |> validate_required([:identity_public_key, :signed_prekey, :signed_prekey_signature])
  end

  def totp_changeset(user, attrs) do
    user
    |> cast(attrs, [:totp_secret])
  end

  def did_changeset(user, attrs) do
    user
    |> cast(attrs, [:did, :rotation_public_key])
    |> validate_required([:did, :rotation_public_key])
    |> unique_constraint(:did)
  end

  defp validate_username(changeset) do
    changeset
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 32)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/,
      message: "must contain only letters, numbers, and underscores"
    )
    |> unique_constraint(:username)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 10, max: 128)
    |> prepare_changes(&hash_password/1)
  end

  defp hash_password(changeset) do
    password = get_change(changeset, :password)

    if password do
      changeset
      |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
