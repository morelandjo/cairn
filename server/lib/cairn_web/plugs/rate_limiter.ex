defmodule MurmuringWeb.Plugs.RateLimiter do
  @moduledoc """
  HTTP API rate limiting plug using ETS token bucket.
  Limits requests per IP (unauthenticated) or per user (authenticated).
  Returns 429 Too Many Requests with Retry-After header when exceeded.
  """

  import Plug.Conn

  @table :http_rate_limiter

  # {rate_per_window, burst, window_ms}
  @limits %{
    # Auth endpoints
    login: {5, 5, 60_000},
    register: {3, 3, 3_600_000},
    auth_general: {20, 20, 60_000},
    # General API
    api_general: {100, 120, 60_000},
    # File upload
    upload: {10, 10, 60_000}
  }

  def start_link do
    GenServer.start_link(__MODULE__.Server, [], name: __MODULE__.Server)
  end

  def child_spec(_opts) do
    %{
      id: __MODULE__.Server,
      start: {__MODULE__, :start_link, []}
    }
  end

  # Plug callbacks

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:murmuring, :http_rate_limiting, true) do
      do_rate_limit(conn)
    else
      conn
    end
  end

  defp do_rate_limit(conn) do
    action = classify_request(conn)
    key = rate_limit_key(conn, action)
    {rate, burst, window_ms} = Map.get(@limits, action, {100, 120, 60_000})

    case check_rate(key, rate, burst, window_ms) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after} ->
        conn
        |> put_resp_header("retry-after", to_string(retry_after))
        |> put_status(429)
        |> Phoenix.Controller.json(%{error: "Too many requests", retry_after: retry_after})
        |> halt()
    end
  end

  # Rate check using ETS token bucket

  defp check_rate(key, rate, burst, window_ms) do
    ensure_table()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{_, tokens, last_time}] ->
        elapsed = now - last_time
        refill = elapsed / window_ms * rate
        current = min(tokens + refill, burst)

        if current >= 1 do
          :ets.insert(@table, {key, current - 1, now})
          :ok
        else
          retry_after = ceil(window_ms / rate / 1_000)
          {:error, :rate_limited, retry_after}
        end

      [] ->
        :ets.insert(@table, {key, burst - 1, now})
        :ok
    end
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [
          :set,
          :named_table,
          :public,
          write_concurrency: true,
          read_concurrency: true
        ])

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  # Classify the request into a rate limit category

  defp classify_request(%{method: "POST", path_info: ["api", "v1", "auth", "login"]}),
    do: :login

  defp classify_request(%{method: "POST", path_info: ["api", "v1", "auth", "register"]}),
    do: :register

  defp classify_request(%{path_info: ["api", "v1", "auth" | _]}),
    do: :auth_general

  defp classify_request(%{method: "POST", path_info: ["api", "v1", "upload"]}),
    do: :upload

  defp classify_request(%{path_info: ["api", "v1" | _]}),
    do: :api_general

  defp classify_request(_conn),
    do: :api_general

  # Key: use user_id if authenticated, otherwise IP

  defp rate_limit_key(conn, action) do
    identifier =
      case conn.assigns[:current_user] do
        %{id: user_id} -> {:user, user_id}
        _ -> {:ip, client_ip(conn)}
      end

    {action, identifier}
  end

  defp client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded |> String.split(",") |> hd() |> String.trim()

      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  # Cleanup server

  defmodule Server do
    @moduledoc false
    use GenServer

    @table :http_rate_limiter
    @cleanup_interval :timer.minutes(1)

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(_opts) do
      # Ensure table exists
      case :ets.info(@table) do
        :undefined ->
          :ets.new(@table, [
            :set,
            :named_table,
            :public,
            write_concurrency: true,
            read_concurrency: true
          ])

        _ ->
          :ok
      end

      schedule_cleanup()
      {:ok, %{}}
    end

    @impl true
    def handle_info(:cleanup, state) do
      now = System.monotonic_time(:millisecond)
      cutoff = now - :timer.minutes(5)

      case :ets.info(@table) do
        :undefined ->
          :ok

        _ ->
          :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
      end

      schedule_cleanup()
      {:noreply, state}
    end

    defp schedule_cleanup do
      Process.send_after(self(), :cleanup, @cleanup_interval)
    end
  end
end
