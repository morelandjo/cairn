defmodule Murmuring.Auth.Token do
  @moduledoc """
  JWT token configuration using Joken.
  """

  use Joken.Config

  @access_token_ttl 15 * 60
  @refresh_token_ttl 7 * 24 * 60 * 60

  @impl true
  def token_config do
    default_claims(default_exp: @access_token_ttl, iss: "murmuring", aud: "murmuring")
  end

  def access_token_ttl, do: @access_token_ttl
  def refresh_token_ttl, do: @refresh_token_ttl

  def generate_access_token(user_id, opts \\ []) do
    extra_claims = %{"sub" => user_id, "type" => "access"}

    extra_claims =
      case Keyword.get(opts, :did) do
        nil -> extra_claims
        did -> Map.put(extra_claims, "did", did)
      end

    generate_and_sign(extra_claims, signer())
  end

  def generate_refresh_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  def verify_access_token(token) do
    case verify_and_validate(token, signer()) do
      {:ok, claims} ->
        if claims["type"] == "access" do
          {:ok, claims}
        else
          {:error, :invalid_token_type}
        end

      {:error, _} = error ->
        error
    end
  end

  defp signer do
    secret = Application.get_env(:murmuring, :jwt_secret, "dev_jwt_secret_change_me")
    Joken.Signer.create("HS256", secret)
  end
end
