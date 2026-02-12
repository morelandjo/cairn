defmodule MurmuringWeb.AuthController do
  use MurmuringWeb, :controller

  alias Murmuring.Accounts
  alias Murmuring.Auth
  alias Murmuring.Auth.PasswordValidator

  def challenge(conn, _params) do
    hmac_key = Application.fetch_env!(:murmuring, :altcha_hmac_key)

    challenge =
      Altcha.create_challenge(%Altcha.ChallengeOptions{
        hmac_key: hmac_key,
        max_number: 100_000
      })

    json(conn, challenge)
  end

  def register(conn, %{"username" => username, "password" => password} = params) do
    with :ok <- check_honeypot(params),
         :ok <- verify_pow(params),
         :ok <- PasswordValidator.validate(password, username),
         {:ok, {user, recovery_codes}} <- Accounts.register_user(params) do
      {:ok, tokens} = Auth.generate_tokens(user)

      conn
      |> put_status(:created)
      |> json(%{
        user: user_json(user),
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        recovery_codes: recovery_codes
      })
    else
      {:error, reason} when is_binary(reason) ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: reason})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  def login(conn, %{"username" => username, "password" => password}) do
    case Accounts.authenticate_user(username, password) do
      {:ok, user} ->
        if user.totp_secret do
          conn |> json(%{requires_totp: true, user_id: user.id})
        else
          {:ok, tokens} = Auth.generate_tokens(user)

          conn
          |> json(%{
            user: user_json(user),
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token
          })
        end

      {:error, :invalid_credentials} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid credentials"})
    end
  end

  def refresh(conn, %{"refresh_token" => refresh_token}) do
    case Auth.rotate_refresh_token(refresh_token) do
      {:ok, tokens} ->
        conn |> json(%{access_token: tokens.access_token, refresh_token: tokens.refresh_token})

      {:error, :invalid_refresh_token} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid or expired refresh token"})
    end
  end

  def recover(conn, %{
        "username" => username,
        "recovery_code" => code,
        "new_password" => new_password
      }) do
    with :ok <- PasswordValidator.validate(new_password, username),
         user when not is_nil(user) <- Accounts.get_user_by_username(username),
         {:ok, _user} <- Accounts.use_recovery_code(user, code) do
      {:ok, updated_user} =
        user
        |> Murmuring.Accounts.User.registration_changeset(%{password: new_password})
        |> Murmuring.Repo.update()

      Auth.revoke_all_user_tokens(user.id)
      {:ok, tokens} = Auth.generate_tokens(updated_user)

      conn
      |> json(%{
        user: user_json(updated_user),
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token
      })
    else
      nil ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid credentials"})

      {:error, :invalid_recovery_code} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid recovery code"})

      {:error, reason} when is_binary(reason) ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: reason})
    end
  end

  def me(conn, _params) do
    user = conn.assigns.current_user
    conn |> json(%{user: user_json(user)})
  end

  defp user_json(user) do
    base = %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      has_totp: user.totp_secret != nil
    }

    if user.did do
      Map.put(base, :did, user.did)
    else
      base
    end
  end

  defp check_honeypot(%{"website" => value}) when byte_size(value) > 0 do
    {:error, "invalid request"}
  end

  defp check_honeypot(_params), do: :ok

  defp verify_pow(params) do
    if Application.get_env(:murmuring, :require_pow, true) do
      hmac_key = Application.fetch_env!(:murmuring, :altcha_hmac_key)

      case params["altcha"] do
        nil ->
          {:error, "proof of work required"}

        payload ->
          if Altcha.verify_solution(payload, hmac_key, false) do
            :ok
          else
            {:error, "invalid proof of work"}
          end
      end
    else
      :ok
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
