defmodule Cairn.Federation.DeliveryWorker do
  @moduledoc """
  Oban worker for delivering ActivityPub activities to remote inboxes.
  Uses exponential backoff with a max of 72 hours.
  """

  use Oban.Worker,
    queue: :federation,
    max_attempts: 15

  require Logger
  alias Cairn.Federation
  alias Cairn.Federation.NodeIdentity
  alias Cairn.Federation.HttpSignatures
  alias Cairn.Federation.MetadataStripper

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "inbox_url" => inbox_url,
      "activity" => activity,
      "federated_node_id" => node_id
    } = args

    # Strip sensitive metadata before sending
    stripped_activity = MetadataStripper.strip(activity)
    body = Jason.encode!(stripped_activity)

    sign_fn = fn message -> NodeIdentity.sign(message) end

    headers =
      HttpSignatures.sign_request(
        "POST",
        inbox_url,
        %{"content-type" => "application/activity+json"},
        body,
        sign_fn
      )

    # Convert headers map to keyword list for Req
    req_headers =
      Enum.map(headers, fn {k, v} -> {k, v} end)

    case Req.post(inbox_url, body: body, headers: req_headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        # Log success
        Federation.log_activity(%{
          federated_node_id: node_id,
          activity_type: activity["type"],
          direction: "outbound",
          actor_uri: activity["actor"],
          object_uri: get_object_uri(activity["object"]),
          payload: activity,
          status: "delivered"
        })

        :ok

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.warning(
          "Federation delivery to #{inbox_url} returned #{status}: #{inspect(resp_body)}"
        )

        Federation.log_activity(%{
          federated_node_id: node_id,
          activity_type: activity["type"],
          direction: "outbound",
          actor_uri: activity["actor"],
          payload: activity,
          status: "failed",
          error: "HTTP #{status}"
        })

        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.warning("Federation delivery to #{inbox_url} failed: #{inspect(reason)}")

        Federation.log_activity(%{
          federated_node_id: node_id,
          activity_type: activity["type"],
          direction: "outbound",
          actor_uri: activity["actor"],
          payload: activity,
          status: "failed",
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @impl Oban.Worker
  @doc "Exponential backoff: 2^attempt minutes, capped at 72 hours."
  def backoff(%Oban.Job{attempt: attempt}) do
    # 72 hours
    max_seconds = 72 * 60 * 60
    min(:math.pow(2, attempt) |> trunc() |> Kernel.*(60), max_seconds)
  end

  @doc "Enqueue a delivery job for an activity to a remote inbox."
  def enqueue(inbox_url, activity, federated_node_id) do
    %{
      inbox_url: inbox_url,
      activity: activity,
      federated_node_id: federated_node_id
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp get_object_uri(object) when is_binary(object), do: object
  defp get_object_uri(%{"id" => id}), do: id
  defp get_object_uri(_), do: nil
end
