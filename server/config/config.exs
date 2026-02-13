# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :cairn,
  ecto_repos: [Cairn.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :cairn, CairnWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CairnWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Cairn.PubSub,
  live_view: [signing_salt: "uF+7O8/J"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :cairn, Cairn.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger with JSON backend for production
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :correlation_id]

config :logger_json, :backend, metadata: [:request_id, :correlation_id, :module]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# File storage configuration
config :cairn, :storage_backend, Cairn.Storage.LocalBackend
config :cairn, Cairn.Storage.LocalBackend, root: Path.expand("priv/uploads")

# Federation configuration
config :cairn, :federation,
  enabled: false,
  domain: "localhost"

# SFU configuration
config :cairn, :sfu_url, "http://localhost:4001"
config :cairn, :sfu_auth_secret, "dev-sfu-secret"
config :cairn, :sfu_client, Cairn.Voice.SfuClient

# TURN configuration
config :cairn, :turn_secret, "dev-turn-secret"
config :cairn, :turn_urls, []

# Meilisearch configuration
config :cairn, :meilisearch,
  url: "http://localhost:7700",
  master_key: nil

# Oban job queue
config :cairn, Oban,
  repo: Cairn.Repo,
  queues: [federation: 10, moderation: 5, search: 5, export: 2, push: 10],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", Cairn.Audit.Pruner}
     ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
