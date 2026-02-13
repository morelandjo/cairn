defmodule Cairn.Federation.HLC do
  @moduledoc """
  Hybrid Logical Clock (HLC) for ordering events across federated nodes.

  Provides monotonic timestamps that combine physical time with a logical counter.
  Drift protection rejects timestamps more than 60 seconds in the future.
  """

  use GenServer

  @max_drift_ms 60_000

  # ── Client API ──

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    node_id = Keyword.get(opts, :node_id, "local")
    GenServer.start_link(__MODULE__, %{node_id: node_id}, name: name)
  end

  @doc "Generate a new HLC timestamp."
  @spec now(atom()) :: {integer(), integer(), String.t()}
  def now(name \\ __MODULE__) do
    GenServer.call(name, :now)
  end

  @doc """
  Update the HLC with a received remote timestamp.
  Returns the new local HLC timestamp.
  """
  @spec update(integer(), integer(), String.t(), atom()) ::
          {:ok, {integer(), integer(), String.t()}} | {:error, :clock_drift}
  def update(remote_wall, remote_counter, remote_node, name \\ __MODULE__) do
    GenServer.call(name, {:update, remote_wall, remote_counter, remote_node})
  end

  @doc "Compare two HLC timestamps. Returns :lt, :eq, or :gt."
  @spec compare({integer(), integer(), String.t()}, {integer(), integer(), String.t()}) ::
          :lt | :eq | :gt
  def compare({w1, c1, n1}, {w2, c2, n2}) do
    cond do
      w1 < w2 -> :lt
      w1 > w2 -> :gt
      c1 < c2 -> :lt
      c1 > c2 -> :gt
      n1 < n2 -> :lt
      n1 > n2 -> :gt
      true -> :eq
    end
  end

  # ── GenServer Callbacks ──

  @impl true
  def init(state) do
    {:ok, Map.merge(state, %{wall: 0, counter: 0})}
  end

  @impl true
  def handle_call(:now, _from, state) do
    physical = System.os_time(:millisecond)
    {new_wall, new_counter} = advance(state.wall, state.counter, physical)
    new_state = %{state | wall: new_wall, counter: new_counter}
    {:reply, {new_wall, new_counter, state.node_id}, new_state}
  end

  @impl true
  def handle_call({:update, remote_wall, remote_counter, _remote_node}, _from, state) do
    physical = System.os_time(:millisecond)

    # Drift protection: reject timestamps > 60s in the future
    if remote_wall - physical > @max_drift_ms do
      {:reply, {:error, :clock_drift}, state}
    else
      {new_wall, new_counter} =
        cond do
          physical > state.wall and physical > remote_wall ->
            {physical, 0}

          state.wall == remote_wall and state.wall == physical ->
            {state.wall, max(state.counter, remote_counter) + 1}

          state.wall == remote_wall ->
            {state.wall, max(state.counter, remote_counter) + 1}

          remote_wall == physical ->
            {remote_wall, remote_counter + 1}

          state.wall == physical ->
            {state.wall, state.counter + 1}

          remote_wall > state.wall ->
            {remote_wall, remote_counter + 1}

          true ->
            {state.wall, state.counter + 1}
        end

      new_state = %{state | wall: new_wall, counter: new_counter}
      {:reply, {:ok, {new_wall, new_counter, state.node_id}}, new_state}
    end
  end

  # ── Private ──

  defp advance(wall, counter, physical) do
    if physical > wall do
      {physical, 0}
    else
      {wall, counter + 1}
    end
  end
end
