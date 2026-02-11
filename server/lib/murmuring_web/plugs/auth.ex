defmodule MurmuringWeb.Plugs.Auth do
  @moduledoc """
  Plug that extracts and verifies Bearer JWT tokens from the Authorization header.
  Assigns `current_user` to the connection on success.
  """

  import Plug.Conn
  alias Murmuring.Auth
  alias Murmuring.Accounts
  alias Murmuring.Bots

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        with {:ok, claims} <- Auth.verify_access_token(token),
             user when not is_nil(user) <- Accounts.get_user(claims["sub"]) do
          assign(conn, :current_user, user)
        else
          _ -> unauthorized(conn)
        end

      ["Bot " <> token] ->
        case Bots.get_bot_by_token(token) do
          nil -> unauthorized(conn)
          bot -> assign(conn, :current_user, bot.user)
        end

      _ ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "unauthorized"})
    |> halt()
  end
end
