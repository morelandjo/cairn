defmodule MurmuringWeb.BotController do
  use MurmuringWeb, :controller

  alias Murmuring.Bots
  alias Murmuring.Servers.Permissions

  # POST /api/v1/servers/:server_id/bots
  def create(conn, %{"server_id" => server_id} = _params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_webhooks") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Bots.create_bot(%{server_id: server_id, creator_id: user_id}) do
        {:ok, result} ->
          conn
          |> put_status(:created)
          |> json(%{
            bot: %{
              id: result.bot_account.id,
              user_id: result.user.id,
              username: result.user.username,
              token: result.token
            }
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # GET /api/v1/servers/:server_id/bots
  def index(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_webhooks") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      bots = Bots.list_bots(server_id)
      json(conn, %{bots: bots})
    end
  end

  # DELETE /api/v1/servers/:server_id/bots/:bid
  def delete(conn, %{"server_id" => server_id, "bid" => bot_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_webhooks") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      bot = Bots.get_bot!(bot_id)
      {:ok, _} = Bots.delete_bot(bot)
      json(conn, %{ok: true})
    end
  end

  # PUT /api/v1/servers/:server_id/bots/:bid/channels
  def update_channels(conn, %{"server_id" => server_id, "bid" => bot_id, "channels" => channels}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_webhooks") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      bot = Bots.get_bot!(bot_id)

      case Bots.update_bot_channels(bot, channels) do
        {:ok, updated} ->
          json(conn, %{bot: %{id: updated.id, allowed_channels: updated.allowed_channels}})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # POST /api/v1/servers/:server_id/bots/:bid/regenerate-token
  def regenerate_token(conn, %{"server_id" => server_id, "bid" => bot_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_webhooks") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      bot = Bots.get_bot!(bot_id)

      case Bots.regenerate_bot_token(bot) do
        {:ok, token} ->
          json(conn, %{token: token})

        {:error, _} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "failed to regenerate token"})
      end
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
