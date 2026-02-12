defmodule Murmuring.Federation.DmHintWorker do
  @moduledoc """
  Oban worker to deliver DM hint (Invite activity) to a remote instance.
  The hint notifies the recipient's home instance that a DM request has been
  created. The recipient can then accept and connect to the initiator's instance.
  """

  use Oban.Worker,
    queue: :federation,
    max_attempts: 10

  require Logger
  alias Murmuring.Federation
  alias Murmuring.Federation.NodeIdentity
  alias Murmuring.Federation.HttpSignatures

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "recipient_instance" => recipient_instance,
      "activity" => activity
    } = args

    inbox_url = "https://#{recipient_instance}/inbox"
    body = Jason.encode!(activity)

    sign_fn = fn message -> NodeIdentity.sign(message) end

    headers =
      HttpSignatures.sign_request(
        "POST",
        inbox_url,
        %{"content-type" => "application/activity+json"},
        body,
        sign_fn
      )

    req_headers = Enum.map(headers, fn {k, v} -> {k, v} end)

    case Req.post(inbox_url, body: body, headers: req_headers, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        Logger.info("DM hint delivered to #{recipient_instance}")
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("DM hint delivery to #{recipient_instance} returned #{status}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.warning("DM hint delivery to #{recipient_instance} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    max_seconds = 24 * 60 * 60
    min(:math.pow(2, attempt) |> trunc() |> Kernel.*(60), max_seconds)
  end

  @doc "Enqueue a DM hint delivery to a remote instance."
  def enqueue(recipient_instance, activity) do
    %{
      recipient_instance: recipient_instance,
      activity: activity
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
