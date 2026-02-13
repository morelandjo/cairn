defmodule Cairn.Chat.LinkPreviewWorker do
  use Oban.Worker, queue: :search, max_attempts: 2

  alias Cairn.Chat.{LinkPreview, SsrfGuard}
  alias Cairn.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"url" => url, "channel_id" => channel_id}}) do
    url_hash = :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)

    # Check cache
    case Repo.get_by(LinkPreview, url_hash: url_hash) do
      %LinkPreview{expires_at: expires_at} = cached ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          broadcast_preview(channel_id, cached)
          :ok
        else
          fetch_and_store(url, url_hash, channel_id)
        end

      nil ->
        fetch_and_store(url, url_hash, channel_id)
    end
  end

  defp fetch_and_store(url, url_hash, channel_id) do
    unless SsrfGuard.safe_url?(url) do
      :ok
    else
      case Req.get(url, max_redirects: 3, receive_timeout: 5_000) do
        {:ok, %{status: 200, body: body}} when is_binary(body) ->
          og = parse_open_graph(body)

          expires_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

          {:ok, preview} =
            %LinkPreview{}
            |> LinkPreview.changeset(%{
              url_hash: url_hash,
              url: url,
              title: og[:title],
              description: og[:description],
              image_url: og[:image],
              site_name: og[:site_name],
              expires_at: expires_at
            })
            |> Repo.insert(on_conflict: :replace_all, conflict_target: :url_hash)

          broadcast_preview(channel_id, preview)
          :ok

        _ ->
          :ok
      end
    end
  end

  defp parse_open_graph(html) do
    # Simple regex-based OG tag parser (no HTML dependency)
    extract = fn property ->
      case Regex.run(~r/<meta[^>]*property="og:#{property}"[^>]*content="([^"]*)"/, html) do
        [_, content] ->
          content

        nil ->
          case Regex.run(~r/<meta[^>]*content="([^"]*)"[^>]*property="og:#{property}"/, html) do
            [_, content] -> content
            nil -> nil
          end
      end
    end

    %{
      title: extract.("title") || extract_title(html),
      description: extract.("description"),
      image: extract.("image"),
      site_name: extract.("site_name")
    }
  end

  defp extract_title(html) do
    case Regex.run(~r/<title[^>]*>([^<]*)<\/title>/, html) do
      [_, title] -> String.trim(title)
      nil -> nil
    end
  end

  defp broadcast_preview(channel_id, preview) do
    Phoenix.PubSub.broadcast(
      Cairn.PubSub,
      "channel:#{channel_id}",
      {:link_preview,
       %{
         url: preview.url,
         title: preview.title,
         description: preview.description,
         image_url: preview.image_url,
         site_name: preview.site_name
       }}
    )
  end
end
