defmodule Cairn.Keys do
  @moduledoc """
  The Keys context — manages X3DH key bundles for end-to-end encryption.
  """

  import Ecto.Query
  alias Cairn.Repo
  alias Cairn.Accounts.User
  alias Cairn.Keys.OneTimePrekey
  alias Cairn.Keys.MlsKeyPackage
  alias Cairn.Keys.KeyBackup

  @doc "Upload a key bundle: identity key, signed prekey, and one-time prekeys"
  def upload_key_bundle(%User{} = user, %{
        identity_public_key: identity_key,
        signed_prekey: signed_prekey,
        signed_prekey_signature: signature,
        one_time_prekeys: otps
      }) do
    Repo.transaction(fn ->
      # Update user's identity key and signed prekey
      changeset =
        User.key_changeset(user, %{
          identity_public_key: identity_key,
          signed_prekey: signed_prekey,
          signed_prekey_signature: signature
        })

      case Repo.update(changeset) do
        {:ok, updated_user} ->
          # Insert one-time prekeys
          prekeys =
            Enum.map(otps, fn otp ->
              %OneTimePrekey{}
              |> OneTimePrekey.changeset(%{
                user_id: user.id,
                key_id: otp.key_id,
                public_key: otp.public_key
              })
              |> Repo.insert!()
            end)

          {updated_user, prekeys}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "Get a user's key bundle, consuming one OTP atomically"
  def get_key_bundle(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        if is_nil(user.identity_public_key) do
          {:error, :no_keys}
        else
          # Atomically consume one unused OTP using FOR UPDATE SKIP LOCKED
          otp = consume_one_prekey(user_id)

          bundle = %{
            identity_public_key: user.identity_public_key,
            signed_prekey: user.signed_prekey,
            signed_prekey_signature: user.signed_prekey_signature,
            one_time_prekey: otp
          }

          {:ok, bundle}
        end
    end
  end

  @doc "Count remaining unconsumed prekeys for a user"
  def count_prekeys(user_id) do
    from(p in OneTimePrekey, where: p.user_id == ^user_id and p.consumed == false)
    |> Repo.aggregate(:count)
  end

  @doc "Rotate signed prekey"
  def rotate_signed_prekey(%User{} = user, attrs) do
    user
    |> User.key_changeset(%{
      identity_public_key: user.identity_public_key,
      signed_prekey: attrs.signed_prekey,
      signed_prekey_signature: attrs.signed_prekey_signature
    })
    |> Repo.update()
  end

  # --- MLS KeyPackages ---

  @max_mls_key_packages 100

  @doc "Upload MLS key packages (max #{@max_mls_key_packages} per call)"
  def upload_mls_key_packages(user_id, packages) when is_list(packages) do
    if length(packages) > @max_mls_key_packages do
      {:error, :too_many_packages}
    else
      inserted =
        Enum.map(packages, fn data ->
          %MlsKeyPackage{}
          |> MlsKeyPackage.changeset(%{user_id: user_id, data: data})
          |> Repo.insert!()
        end)

      {:ok, inserted}
    end
  end

  @doc "Atomically consume one unconsumed MLS key package for a user"
  def consume_mls_key_package(user_id) do
    subquery =
      from(kp in MlsKeyPackage,
        where: kp.user_id == ^user_id and kp.consumed == false,
        limit: 1,
        order_by: [asc: kp.inserted_at],
        lock: "FOR UPDATE SKIP LOCKED"
      )

    case Repo.one(subquery) do
      nil ->
        {:error, :exhausted}

      key_package ->
        key_package
        |> Ecto.Changeset.change(consumed: true)
        |> Repo.update!()

        {:ok, %{id: key_package.id, data: key_package.data}}
    end
  end

  @doc "Count unconsumed MLS key packages for a user"
  def count_mls_key_packages(user_id) do
    from(kp in MlsKeyPackage, where: kp.user_id == ^user_id and kp.consumed == false)
    |> Repo.aggregate(:count)
  end

  # --- Key Backups ---

  @doc "Upsert a key backup for a user (one backup per user)"
  def upsert_key_backup(user_id, data) when is_binary(data) do
    size = byte_size(data)

    case Repo.get_by(KeyBackup, user_id: user_id) do
      nil ->
        %KeyBackup{}
        |> KeyBackup.changeset(%{user_id: user_id, data: data, size_bytes: size})
        |> Repo.insert()

      existing ->
        existing
        |> KeyBackup.changeset(%{data: data, size_bytes: size})
        |> Repo.update()
    end
  end

  @doc "Get the key backup for a user"
  def get_key_backup(user_id) do
    Repo.get_by(KeyBackup, user_id: user_id)
  end

  @doc "Delete the key backup for a user"
  def delete_key_backup(user_id) do
    case Repo.get_by(KeyBackup, user_id: user_id) do
      nil -> {:error, :not_found}
      backup -> Repo.delete(backup)
    end
  end

  defp consume_one_prekey(user_id) do
    # Use a subquery with FOR UPDATE SKIP LOCKED to atomically claim one prekey
    subquery =
      from(p in OneTimePrekey,
        where: p.user_id == ^user_id and p.consumed == false,
        limit: 1,
        order_by: [asc: p.key_id],
        lock: "FOR UPDATE SKIP LOCKED"
      )

    case Repo.one(subquery) do
      nil ->
        nil

      prekey ->
        prekey
        |> Ecto.Changeset.change(consumed: true)
        |> Repo.update!()

        %{key_id: prekey.key_id, public_key: prekey.public_key}
    end
  end
end
