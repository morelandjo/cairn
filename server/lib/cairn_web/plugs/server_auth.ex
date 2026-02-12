defmodule CairnWeb.Plugs.ServerAuth do
  @moduledoc """
  Plug that checks server-level permissions for the current user.

  Usage in controller:
    plug ServerAuth, permission: "manage_channels" when action in [:create]
    plug ServerAuth, permission: "read_messages" when action in [:show, :messages]

  Requires `current_user` to be set on conn (via Auth plug).
  Extracts server context from channel's server_id or route params.
  DM channels bypass all permission checks.
  """

  import Plug.Conn
  alias Cairn.Chat
  alias Cairn.Servers.Permissions

  def init(opts), do: opts

  def call(conn, opts) do
    permission = Keyword.get(opts, :permission)
    user_id = conn.assigns.current_user.id

    case resolve_server_id(conn) do
      {:dm, _} ->
        # DMs bypass server permission checks
        conn

      {:ok, server_id} ->
        if Permissions.has_permission?(server_id, user_id, permission) do
          conn
        else
          conn
          |> put_status(:forbidden)
          |> Phoenix.Controller.json(%{error: "insufficient permissions"})
          |> halt()
        end

      :no_server ->
        # No server context — allow (backward compat for flat channel routes)
        conn
    end
  end

  defp resolve_server_id(conn) do
    cond do
      # Direct server_id in route params
      conn.params["server_id"] ->
        {:ok, conn.params["server_id"]}

      # Channel ID in route — look up channel's server
      conn.params["id"] ->
        case Chat.get_channel(conn.params["id"]) do
          nil -> :no_server
          %{type: "dm"} -> {:dm, nil}
          %{server_id: nil} -> :no_server
          %{server_id: server_id} -> {:ok, server_id}
        end

      # server_id in body params (e.g., channel creation)
      conn.body_params["server_id"] ->
        {:ok, conn.body_params["server_id"]}

      true ->
        :no_server
    end
  end
end
