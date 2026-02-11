defmodule MurmuringWeb.TotpController do
  use MurmuringWeb, :controller

  alias Murmuring.Accounts
  alias Murmuring.Auth

  def enable(conn, _params) do
    secret = NimbleTOTP.secret()

    uri =
      NimbleTOTP.otpauth_uri("murmuring:#{conn.assigns.current_user.username}", secret,
        issuer: "Murmuring"
      )

    conn
    |> json(%{
      secret: Base.encode32(secret, padding: false),
      uri: uri
    })
  end

  def verify(conn, %{"code" => code, "secret" => encoded_secret}) do
    user = conn.assigns.current_user
    secret = Base.decode32!(encoded_secret, padding: false)

    if NimbleTOTP.valid?(secret, code) do
      {:ok, _user} = Accounts.update_user_totp(user, %{totp_secret: secret})
      conn |> json(%{status: "totp_enabled"})
    else
      conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid TOTP code"})
    end
  end

  def disable(conn, %{"code" => code}) do
    user = conn.assigns.current_user

    if user.totp_secret && NimbleTOTP.valid?(user.totp_secret, code) do
      {:ok, _user} = Accounts.update_user_totp(user, %{totp_secret: nil})
      conn |> json(%{status: "totp_disabled"})
    else
      conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid TOTP code"})
    end
  end

  def authenticate(conn, %{"user_id" => user_id, "code" => code}) do
    user = Accounts.get_user!(user_id)

    if user.totp_secret && NimbleTOTP.valid?(user.totp_secret, code) do
      {:ok, tokens} = Auth.generate_tokens(user)

      conn
      |> json(%{
        user: %{
          id: user.id,
          username: user.username,
          display_name: user.display_name,
          has_totp: true
        },
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token
      })
    else
      conn |> put_status(:unauthorized) |> json(%{error: "invalid TOTP code"})
    end
  end
end
