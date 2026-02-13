defmodule Cairn.Export.DataExportWorker do
  use Oban.Worker, queue: :export, max_attempts: 3

  alias Cairn.Export

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    {:ok, _result} = Export.generate_export(user_id)
    :ok
  end
end
