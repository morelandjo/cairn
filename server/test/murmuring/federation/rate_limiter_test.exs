defmodule Murmuring.Federation.FederationRateLimiterTest do
  use ExUnit.Case, async: false

  alias Murmuring.Federation.FederationRateLimiter

  setup do
    # Clean up Redis key before each test
    domain = "ratelimit-test-#{:erlang.unique_integer([:positive])}.example.com"
    Redix.command(:murmuring_redis, ["DEL", "federation:rate:#{domain}"])
    %{domain: domain}
  end

  test "allows requests under the limit", %{domain: domain} do
    assert :ok = FederationRateLimiter.check(domain)
    assert FederationRateLimiter.current_count(domain) == 1
  end

  test "allows up to burst limit", %{domain: domain} do
    # Default burst is 200
    for _ <- 1..200 do
      assert :ok = FederationRateLimiter.check(domain)
    end

    assert FederationRateLimiter.current_count(domain) == 200
  end

  test "rejects requests over burst limit", %{domain: domain} do
    # Fill up to burst
    for _ <- 1..200 do
      FederationRateLimiter.check(domain)
    end

    # Next request should be rate limited
    assert {:error, :rate_limited} = FederationRateLimiter.check(domain)
  end

  test "current_count returns 0 for unknown domain" do
    assert FederationRateLimiter.current_count(
             "nonexistent-#{System.unique_integer([:positive])}.example.com"
           ) == 0
  end
end
