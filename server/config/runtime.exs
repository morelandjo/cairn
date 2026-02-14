import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/cairn start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :cairn, CairnWeb.Endpoint, server: true
end

config :cairn, CairnWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Redis URL (defaults to localhost:6380 for local dev; CI and prod override via env)
if redis_url = System.get_env("REDIS_URL") do
  config :cairn, :redis_url, redis_url
end

# JWT secret (required in prod, optional in dev/test)
if jwt_secret = System.get_env("JWT_SECRET") do
  config :cairn, :jwt_secret, jwt_secret
end

# Storage backend selection
case System.get_env("STORAGE_BACKEND") do
  "s3" ->
    config :cairn, :storage_backend, Cairn.Storage.S3Backend

    config :cairn, Cairn.Storage.S3Backend,
      bucket: System.get_env("S3_BUCKET") || "cairn-uploads",
      endpoint: System.get_env("S3_ENDPOINT"),
      region: System.get_env("AWS_REGION", "us-east-1")

    config :ex_aws,
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")

  _ ->
    :ok
end

# Meilisearch configuration from environment
if meili_url = System.get_env("MEILI_URL") do
  config :cairn, :meilisearch,
    url: meili_url,
    master_key: System.get_env("MEILI_MASTER_KEY")
end

# SSL enforcement (runtime-configurable via FORCE_SSL env var)
# Only override if the env var is explicitly set; otherwise use the compile-time default.
force_ssl_env = System.get_env("FORCE_SSL")

if force_ssl_env != nil do
  config :cairn, :force_ssl, force_ssl_env != "false"
end

# Federation configuration from environment
federation_enabled = System.get_env("FEDERATION_ENABLED") in ~w(true 1)

if federation_enabled do
  if force_ssl_env == "false" do
    IO.puts(:stderr,
      "[warning] Federation without SSL — transport is unencrypted. " <>
      "Federation metadata and public channel content can be intercepted in transit."
    )
  end

  allow_insecure = System.get_env("FEDERATION_ALLOW_INSECURE") in ~w(true 1)

  config :cairn, :federation,
    enabled: true,
    allow_insecure: allow_insecure,
    domain: System.get_env("CAIRN_DOMAIN") || "localhost",
    node_key_path: System.get_env("NODE_KEY_PATH")
end

# Allow CAIRN_DOMAIN to be set even without federation (used for TURN, endpoint host, etc.)
if domain = System.get_env("CAIRN_DOMAIN") do
  config :cairn, :domain, domain
end

# SFU configuration from environment
if sfu_url = System.get_env("SFU_URL") do
  config :cairn, :sfu_url, sfu_url
end

if sfu_secret = System.get_env("SFU_AUTH_SECRET") do
  config :cairn, :sfu_auth_secret, sfu_secret
end

# TURN configuration from environment
if turn_secret = System.get_env("TURN_SECRET") do
  config :cairn, :turn_secret, turn_secret
end

if turn_urls = System.get_env("TURN_URLS") do
  config :cairn, :turn_urls, String.split(turn_urls, ",", trim: true)
end

# ALTCHA proof-of-work HMAC key (required in prod)
if altcha_key = System.get_env("ALTCHA_HMAC_KEY") do
  config :cairn, :altcha_hmac_key, altcha_key
end

if config_env() == :prod do
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  repo_config =
    if database_url = System.get_env("DATABASE_URL") do
      [url: database_url]
    else
      # Individual env vars avoid URL-encoding issues with special characters in passwords
      [
        hostname: System.get_env("PGHOST") || "localhost",
        port: String.to_integer(System.get_env("PGPORT") || "5432"),
        username: System.get_env("PGUSER") || "cairn",
        password:
          System.get_env("PGPASSWORD") ||
            raise("environment variable PGPASSWORD or DATABASE_URL is required"),
        database: System.get_env("PGDATABASE") || "cairn"
      ]
    end

  config :cairn, Cairn.Repo,
    [{:pool_size, String.to_integer(System.get_env("POOL_SIZE") || "10")},
     {:socket_options, maybe_ipv6} | repo_config]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || System.get_env("CAIRN_DOMAIN") || "example.com"
  prod_force_ssl = Application.get_env(:cairn, :force_ssl, true)

  config :cairn, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  url_config =
    if prod_force_ssl do
      [host: host, port: 443, scheme: "https"]
    else
      [host: host, port: String.to_integer(System.get_env("PORT", "4000")), scheme: "http"]
    end

  config :cairn, CairnWeb.Endpoint,
    url: url_config,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :cairn, CairnWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :cairn, CairnWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :cairn, Cairn.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
