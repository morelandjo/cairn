defmodule CairnWeb.Plugs.RequireSsl do
  @moduledoc """
  Runtime-configurable SSL redirect plug.

  When `config :cairn, :force_ssl` is true, redirects HTTP requests to HTTPS.
  Unlike Phoenix's built-in `force_ssl` (which is compile-time), this reads the
  config at runtime so it can be toggled via the `FORCE_SSL` environment variable.

  Skips redirection for localhost, 127.0.0.1, and the /health endpoint.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:cairn, :force_ssl, true) and not secure?(conn) and not skip?(conn) do
      url = "https://#{conn.host}#{port_suffix(conn)}#{conn.request_path}#{query_string(conn)}"

      conn
      |> put_resp_header("location", url)
      |> send_resp(301, "")
      |> halt()
    else
      conn
    end
  end

  defp secure?(conn) do
    conn.scheme == :https or
      Plug.Conn.get_req_header(conn, "x-forwarded-proto") == ["https"]
  end

  defp skip?(conn) do
    conn.host in ["localhost", "127.0.0.1"] or
      conn.request_path == "/health"
  end

  defp port_suffix(conn) do
    case conn.port do
      80 -> ""
      443 -> ""
      port -> ":#{port}"
    end
  end

  defp query_string(%{query_string: ""}), do: ""
  defp query_string(%{query_string: qs}), do: "?#{qs}"
end
