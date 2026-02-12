defmodule Murmuring.Export.DataExportWorker do
  use Oban.Worker, queue: :export, max_attempts: 3

  alias Murmuring.Export

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Export.generate_export(user_id) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
