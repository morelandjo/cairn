defmodule CairnWeb.SearchController do
  use CairnWeb, :controller

  alias Cairn.{Chat, Search, Servers}

  # GET /api/v1/servers/:server_id/search?q=...&channel_id=...
  def search(conn, %{"server_id" => server_id, "q" => query} = params) do
    user_id = conn.assigns.current_user.id

    unless Servers.is_member?(server_id, user_id) do
      conn |> put_status(:forbidden) |> json(%{error: "not a member"})
    else
      # Get channels the user can read in this server
      channels = Chat.list_user_server_channels(server_id, user_id)
      channel_ids = Enum.map(channels, & &1.id)

      # Filter by specific channel if requested
      channel_ids =
        case params["channel_id"] do
          nil -> channel_ids
          cid -> if cid in channel_ids, do: [cid], else: []
        end

      case Search.search(query, channel_ids: channel_ids) do
        {:ok, hits} ->
          json(conn, %{results: hits})

        {:error, reason} ->
          conn
          |> put_status(:service_unavailable)
          |> json(%{error: "search unavailable", details: inspect(reason)})
      end
    end
  end
end
