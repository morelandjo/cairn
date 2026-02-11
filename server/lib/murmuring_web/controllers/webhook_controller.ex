defmodule MurmuringWeb.WebhookController do
  use MurmuringWeb, :controller

  alias Murmuring.Bots
  alias Murmuring.Servers.Permissions

  # POST /api/v1/webhooks/:token (no auth needed — token IS auth)
  def execute(conn, %{"token" => token} = params) do
    case Bots.execute_webhook(token, params) do
      {:ok, message} ->
        conn |> put_status(:created) |> json(%{message: %{id: message.id}})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "webhook not found"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  # GET /api/v1/servers/:server_id/webhooks
  def index(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_webhooks") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      webhooks = Bots.list_webhooks(server_id)

      json(conn, %{
        webhooks:
          Enum.map(webhooks, fn w ->
            %{id: w.id, name: w.name, channel_id: w.channel_id, avatar_key: w.avatar_key}
          end)
      })
    end
  end

  # POST /api/v1/servers/:server_id/webhooks
  def create(conn, %{"server_id" => server_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_webhooks") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Bots.create_webhook(%{
             name: params["name"],
             server_id: server_id,
             channel_id: params["channel_id"],
             creator_id: user_id
           }) do
        {:ok, webhook} ->
          conn
          |> put_status(:created)
          |> json(%{
            webhook: %{
              id: webhook.id,
              name: webhook.name,
              token: webhook.token,
              channel_id: webhook.channel_id
            }
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:server_id/webhooks/:wid
  def delete(conn, %{"server_id" => server_id, "wid" => webhook_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_webhooks") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      webhook = Murmuring.Repo.get!(Murmuring.Bots.Webhook, webhook_id)
      {:ok, _} = Bots.delete_webhook(webhook)
      json(conn, %{ok: true})
    end
  end

  # POST /api/v1/servers/:server_id/webhooks/:wid/regenerate-token
  def regenerate_token(conn, %{"server_id" => server_id, "wid" => webhook_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_webhooks") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      webhook = Murmuring.Repo.get!(Murmuring.Bots.Webhook, webhook_id)

      case Bots.regenerate_webhook_token(webhook) do
        {:ok, updated} ->
          json(conn, %{webhook: %{id: updated.id, token: updated.token}})

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
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
