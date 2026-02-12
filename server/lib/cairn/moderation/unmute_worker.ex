defmodule Murmuring.Moderation.UnmuteWorker do
  use Oban.Worker, queue: :moderation, max_attempts: 3

  alias Murmuring.Moderation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"mute_id" => mute_id}}) do
    case Moderation.get_mute(mute_id) do
      nil -> :ok
      mute -> Moderation.delete_mute(mute)
    end

    :ok
  end
end
