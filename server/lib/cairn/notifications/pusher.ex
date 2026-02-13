defmodule Cairn.Notifications.Pusher do
  @moduledoc """
  Oban worker that sends push notifications via the Expo Push API.
  Privacy-first: never includes message content, sender name, or identifiable info.
  """

  use Oban.Worker,
    queue: :push,
    max_attempts: 5

  require Logger
  alias Cairn.Notifications

  @expo_push_url "https://exp.host/--/api/v2/push/send"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "channel_id" => channel_id,
      "channel_name" => channel_name,
      "server_id" => server_id,
      "author_id" => author_id
    } = args

    # Get push tokens for offline users in the channel
    tokens = Notifications.get_push_tokens_for_channel(channel_id, exclude: author_id)

    if tokens == [] do
      :ok
    else
      # Privacy-first payload: no message content or sender info
      messages =
        Enum.map(tokens, fn push_token ->
          %{
            "to" => push_token.token,
            "title" => "Cairn",
            "body" => "New message in ##{channel_name}",
            "data" => %{
              "channel_id" => channel_id,
              "server_id" => server_id
            },
            "sound" => "default",
            "priority" => "high"
          }
        end)

      send_push(messages)
    end
  end

  defp send_push(messages) do
    body = Jason.encode!(messages)

    case Req.post(@expo_push_url,
           body: body,
           headers: [{"content-type", "application/json"}],
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200}} ->
        Logger.debug("Push notifications sent: #{length(messages)} messages")
        :ok

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.warning("Expo Push API returned #{status}: #{inspect(resp_body)}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.warning("Expo Push API failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 2^attempt seconds, capped at 5 minutes
    min(:math.pow(2, attempt) |> trunc(), 300)
  end

  @doc "Enqueue a push notification job for a new message in a channel."
  def enqueue(channel_id, channel_name, server_id, author_id) do
    %{
      channel_id: channel_id,
      channel_name: channel_name,
      server_id: server_id,
      author_id: author_id
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
