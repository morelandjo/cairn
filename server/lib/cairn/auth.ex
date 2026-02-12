defmodule Cairn.Auth do
  @moduledoc """
  The Auth context — token generation, refresh rotation, account recovery.
  """

  import Ecto.Query
  alias Cairn.Repo
  alias Cairn.Auth.{Token, RefreshToken}

  def generate_tokens(user) do
    token_opts = if user.did, do: [did: user.did], else: []
    {:ok, access_token, _claims} = Token.generate_access_token(user.id, token_opts)
    raw_refresh = Token.generate_refresh_token()
    refresh_hash = hash_token(raw_refresh)

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(Token.refresh_token_ttl(), :second)
      |> DateTime.truncate(:second)

    %RefreshToken{}
    |> RefreshToken.changeset(%{
      token_hash: refresh_hash,
      user_id: user.id,
      expires_at: expires_at
    })
    |> Repo.insert!()

    {:ok, %{access_token: access_token, refresh_token: raw_refresh}}
  end

  def verify_access_token(token) do
    Token.verify_access_token(token)
  end

  def rotate_refresh_token(raw_token) do
    token_hash = hash_token(raw_token)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query =
      from rt in RefreshToken,
        where: rt.token_hash == ^token_hash and is_nil(rt.revoked_at) and rt.expires_at > ^now,
        preload: [:user]

    case Repo.one(query) do
      nil ->
        {:error, :invalid_refresh_token}

      refresh_token ->
        # Revoke old token
        refresh_token
        |> RefreshToken.revoke_changeset()
        |> Repo.update!()

        # Generate new tokens
        generate_tokens(refresh_token.user)
    end
  end

  def revoke_all_user_tokens(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(rt in RefreshToken,
      where: rt.user_id == ^user_id and is_nil(rt.revoked_at)
    )
    |> Repo.update_all(set: [revoked_at: now])
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
