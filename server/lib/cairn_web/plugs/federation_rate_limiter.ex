defmodule MurmuringWeb.Plugs.FederationRateLimiter do
  @moduledoc """
  Plug that rate-limits federation inbox requests per remote node domain.
  Returns 429 Too Many Requests when the limit is exceeded.
  """

  import Plug.Conn
  alias Murmuring.Federation.FederationRateLimiter

  def init(opts), do: opts

  def call(conn, _opts) do
    # Determine the remote domain from the request
    domain = get_remote_domain(conn)

    case FederationRateLimiter.check(domain) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        conn
        |> put_status(429)
        |> put_resp_header("retry-after", "60")
        |> Phoenix.Controller.json(%{error: "Rate limit exceeded"})
        |> halt()
    end
  end

  defp get_remote_domain(conn) do
    # Try the federation_node assign first (set by VerifyHttpSignature)
    case conn.assigns[:federation_node] do
      %{domain: domain} ->
        domain

      _ ->
        # Fall back to Host header
        case Plug.Conn.get_req_header(conn, "host") do
          [host | _] -> host |> String.split(":") |> hd()
          [] -> "unknown"
        end
    end
  end
end
