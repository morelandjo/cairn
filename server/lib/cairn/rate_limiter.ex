defmodule Murmuring.RateLimiter do
  @moduledoc """
  ETS-based token bucket rate limiter.
  Configurable per-action limits with burst support.
  """

  use GenServer

  @table :rate_limiter
  @cleanup_interval :timer.minutes(1)

  @limits %{
    message: {10, 20, 1_000},
    typing: {1, 1, 3_000},
    speaking: {5, 5, 1_000}
  }

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if an action is allowed for a given key.
  Returns :ok or {:error, :rate_limited}.
  """
  def check(action, key) do
    {rate, burst, window_ms} = Map.get(@limits, action, {10, 20, 1_000})
    bucket_key = {action, key}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, bucket_key) do
      [{_, tokens, last_time}] ->
        elapsed = now - last_time
        refill = elapsed / window_ms * rate
        current = min(tokens + refill, burst)

        if current >= 1 do
          :ets.insert(@table, {bucket_key, current - 1, now})
          :ok
        else
          {:error, :rate_limited}
        end

      [] ->
        :ets.insert(@table, {bucket_key, burst - 1, now})
        :ok
    end
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :named_table,
      :public,
      write_concurrency: true,
      read_concurrency: true
    ])

    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - :timer.minutes(5)

    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
