defmodule Cairn.Federation.FederationRateLimiter do
  @moduledoc """
  Per-node rate limiter for federation inbox requests.
  Default: 100 requests/minute, burst up to 200.
  Uses Redis for distributed state.
  """

  @default_limit 100
  @default_burst 200
  @window_seconds 60

  @doc """
  Check if a request from a domain should be allowed.
  Returns :ok or {:error, :rate_limited}.
  """
  @spec check(String.t()) :: :ok | {:error, :rate_limited}
  def check(domain) do
    config = Application.get_env(:cairn, :federation, [])
    burst = Keyword.get(config, :rate_burst, @default_burst)

    key = "federation:rate:#{domain}"

    case Redix.command(:cairn_redis, ["INCR", key]) do
      {:ok, count} when count == 1 ->
        # First request in window — set expiry
        Redix.command(:cairn_redis, ["EXPIRE", key, @window_seconds])
        :ok

      {:ok, count} when count <= burst ->
        :ok

      {:ok, _count} ->
        {:error, :rate_limited}

      {:error, _} ->
        # Redis unavailable — allow through
        :ok
    end
  end

  @doc "Get the current request count for a domain."
  @spec current_count(String.t()) :: integer()
  def current_count(domain) do
    key = "federation:rate:#{domain}"

    case Redix.command(:cairn_redis, ["GET", key]) do
      {:ok, nil} -> 0
      {:ok, count} -> String.to_integer(count)
      {:error, _} -> 0
    end
  end
end
