defmodule Murmuring.Accounts do
  @moduledoc """
  The Accounts context — user registration, lookup, and password verification.
  """

  import Ecto.Query
  alias Murmuring.Repo
  alias Murmuring.Accounts.{User, RecoveryCode}

  def register_user(attrs) do
    Repo.transaction(fn ->
      case %User{}
           |> User.registration_changeset(attrs)
           |> Repo.insert() do
        {:ok, user} ->
          codes = generate_recovery_codes(user)
          {user, codes}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def authenticate_user(username, password) do
    user = get_user_by_username(username)

    cond do
      user && Argon2.verify_pass(password, user.password_hash) ->
        {:ok, user}

      user ->
        {:error, :invalid_credentials}

      true ->
        Argon2.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_username(username) do
    Repo.get_by(User, username: username)
  end

  def update_user_totp(%User{} = user, attrs) do
    user
    |> User.totp_changeset(attrs)
    |> Repo.update()
  end

  def update_user_keys(%User{} = user, attrs) do
    user
    |> User.key_changeset(attrs)
    |> Repo.update()
  end

  def update_user_did(%User{} = user, attrs) do
    user
    |> User.did_changeset(attrs)
    |> Repo.update()
  end

  def get_user_by_did(did) do
    Repo.get_by(User, did: did)
  end

  def use_recovery_code(%User{} = user, code) do
    query =
      from rc in RecoveryCode,
        where: rc.user_id == ^user.id and is_nil(rc.used_at),
        select: rc

    unused_codes = Repo.all(query)

    found =
      Enum.find(unused_codes, fn rc ->
        Argon2.verify_pass(code, rc.code_hash)
      end)

    if found do
      found
      |> Ecto.Changeset.change(used_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()

      {:ok, user}
    else
      Argon2.no_user_verify()
      {:error, :invalid_recovery_code}
    end
  end

  defp generate_recovery_codes(user) do
    codes =
      for _ <- 1..12 do
        code = :crypto.strong_rand_bytes(5) |> Base.encode32(case: :lower, padding: false)
        code
      end

    Enum.each(codes, fn code ->
      %RecoveryCode{}
      |> RecoveryCode.changeset(%{
        user_id: user.id,
        code_hash: Argon2.hash_pwd_salt(code)
      })
      |> Repo.insert!()
    end)

    codes
  end
end
