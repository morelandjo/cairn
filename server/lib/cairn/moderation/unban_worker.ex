defmodule Cairn.Moderation.UnbanWorker do
  use Oban.Worker, queue: :moderation, max_attempts: 3

  alias Cairn.Moderation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ban_id" => ban_id}}) do
    case Moderation.get_ban(ban_id) do
      nil -> :ok
      ban -> Moderation.delete_ban(ban)
    end

    :ok
  end
end
