defmodule MurmuringWeb.SpaController do
  @moduledoc """
  Serves the web client SPA with runtime configuration injection.

  In production, the built web client (client/web/dist/) is placed at
  priv/static/app/. This controller serves index.html with a
  `window.__MURMURING_CONFIG__` script tag injected.
  """

  use MurmuringWeb, :controller

  @index_cache_key :spa_index_html

  def index(conn, _params) do
    case get_index_html() do
      {:ok, html} ->
        injected = inject_config(html)

        conn
        |> put_resp_header("content-type", "text/html; charset=utf-8")
        |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
        |> send_resp(200, injected)

      :error ->
        conn
        |> put_status(404)
        |> json(%{error: "Web client not installed. Place client/web/dist/ in priv/static/app/"})
    end
  end

  defp get_index_html do
    case :persistent_term.get(@index_cache_key, nil) do
      nil ->
        path = index_path()

        if File.exists?(path) do
          html = File.read!(path)
          :persistent_term.put(@index_cache_key, html)
          {:ok, html}
        else
          :error
        end

      html ->
        {:ok, html}
    end
  end

  defp index_path do
    Path.join(:code.priv_dir(:murmuring), "static/app/index.html")
  end

  defp inject_config(html) do
    config = runtime_config()
    script = "<script>window.__MURMURING_CONFIG__=#{Jason.encode!(config)};</script>"

    # Insert before closing </head> tag
    String.replace(html, "</head>", "#{script}\n</head>", global: false)
  end

  defp runtime_config do
    federation_config = Application.get_env(:murmuring, :federation, [])

    %{
      domain: Keyword.get(federation_config, :domain, "localhost"),
      instance_name: Application.get_env(:murmuring, :instance_name, "Murmuring"),
      federation_enabled: Keyword.get(federation_config, :enabled, false),
      max_upload_size: Application.get_env(:murmuring, :max_upload_size, 10_485_760),
      voice_enabled: Application.get_env(:murmuring, :voice_enabled, true),
      force_ssl: Application.get_env(:murmuring, :force_ssl, true),
      version: "0.1.0"
    }
  end
end
