defmodule Cairn.Search do
  @moduledoc """
  Meilisearch client wrapper for full-text message search.
  Uses Req directly (no extra dependency).
  """

  def index_message(message) do
    doc = %{
      id: message.id,
      content: message.content,
      author_id: message.author_id,
      channel_id: message.channel_id,
      inserted_at: message.inserted_at
    }

    case meili_post("/indexes/messages/documents", [doc]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def search(query, opts \\ []) do
    channel_ids = Keyword.get(opts, :channel_ids, [])
    limit = Keyword.get(opts, :limit, 20)

    filter =
      if channel_ids != [] do
        channel_filter =
          channel_ids
          |> Enum.map(fn id -> "channel_id = \"#{id}\"" end)
          |> Enum.join(" OR ")

        [channel_filter]
      else
        []
      end

    body = %{
      q: query,
      limit: limit,
      filter: filter,
      attributesToRetrieve: ["id", "content", "author_id", "channel_id", "inserted_at"]
    }

    case meili_post("/indexes/messages/search", body) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Map.get(body, "hits", [])}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def ensure_index do
    meili_post("/indexes", %{uid: "messages", primaryKey: "id"})

    meili_put("/indexes/messages/settings", %{
      filterableAttributes: ["channel_id", "author_id"],
      sortableAttributes: ["inserted_at"],
      searchableAttributes: ["content"]
    })
  end

  defp meili_post(path, body) do
    url = meili_url() <> path

    Req.post(url,
      json: body,
      headers: meili_headers()
    )
  end

  defp meili_put(path, body) do
    url = meili_url() <> path

    Req.put(url,
      json: body,
      headers: meili_headers()
    )
  end

  defp meili_url do
    Application.get_env(:cairn, :meilisearch, [])
    |> Keyword.get(:url, "http://localhost:7700")
  end

  defp meili_headers do
    key =
      Application.get_env(:cairn, :meilisearch, [])
      |> Keyword.get(:master_key)

    if key do
      [{"Authorization", "Bearer #{key}"}]
    else
      []
    end
  end
end
