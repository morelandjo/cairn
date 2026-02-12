defmodule CairnWeb.DiscoveryController do
  use CairnWeb, :controller

  alias Cairn.Discovery
  alias Cairn.Servers.Permissions

  # GET /api/v1/directory
  def index(conn, params) do
    entries =
      Discovery.list_directory(
        limit: min(String.to_integer(params["limit"] || "50"), 100),
        offset: String.to_integer(params["offset"] || "0"),
        tag: params["tag"]
      )

    json(conn, %{servers: entries})
  end

  # POST /api/v1/servers/:server_id/directory/list
  def list(conn, %{"server_id" => server_id} = params) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_server") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      case Discovery.list_server(server_id, %{
             description: params["description"],
             tags: params["tags"] || []
           }) do
        {:ok, entry} ->
          conn
          |> put_status(:created)
          |> json(%{
            entry: %{
              id: entry.id,
              server_id: entry.server_id,
              description: entry.description,
              tags: entry.tags,
              member_count: entry.member_count,
              listed_at: entry.listed_at
            }
          })

        {:error, changeset} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  # DELETE /api/v1/servers/:server_id/directory/unlist
  def unlist(conn, %{"server_id" => server_id}) do
    user_id = conn.assigns.current_user.id

    unless Permissions.has_permission?(server_id, user_id, "manage_server") do
      conn |> put_status(:forbidden) |> json(%{error: "insufficient permissions"})
    else
      {:ok, _} = Discovery.unlist_server(server_id)
      json(conn, %{ok: true})
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
