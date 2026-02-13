defmodule CairnWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Plug that sets security-related HTTP response headers.
  Applied to all responses.
  """

  import Plug.Conn

  @headers [
    {"x-frame-options", "DENY"},
    {"x-content-type-options", "nosniff"},
    {"referrer-policy", "strict-origin-when-cross-origin"},
    {"permissions-policy", "camera=(), microphone=(), geolocation=()"},
    {"x-xss-protection", "0"},
    {"cross-origin-opener-policy", "same-origin"}
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_security_headers()
    |> put_hsts_header()
    |> put_csp_header()
  end

  defp put_security_headers(conn) do
    Enum.reduce(@headers, conn, fn {key, value}, acc ->
      put_resp_header(acc, key, value)
    end)
  end

  defp put_hsts_header(conn) do
    if Application.get_env(:cairn, :force_ssl, false) do
      put_resp_header(conn, "strict-transport-security", "max-age=31536000; includeSubDomains")
    else
      conn
    end
  end

  defp put_csp_header(conn) do
    csp =
      Application.get_env(:cairn, :content_security_policy, default_csp())

    put_resp_header(conn, "content-security-policy", csp)
  end

  defp default_csp do
    [
      "default-src 'self'",
      "script-src 'self'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob:",
      "connect-src 'self' wss:",
      "font-src 'self'",
      "media-src 'self' blob:",
      "object-src 'none'",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'self'"
    ]
    |> Enum.join("; ")
  end
end
