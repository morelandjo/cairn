import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :cairn, Cairn.Repo,
  username: System.get_env("PGUSER", "cairn"),
  password: System.get_env("PGPASSWORD", "cairn_dev"),
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5433")),
  database: "cairn_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :cairn, CairnWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "uB6KL49lGvfQGndOTURMH5YDhgINERVHPwCqbMgijfNtTUpJsJhue7E2/Zpri/Hl",
  server: false

# In test we don't send emails
config :cairn, Cairn.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# JWT secret for test
config :cairn, :jwt_secret, "test_jwt_secret_not_real"

# Speed up password hashing in tests
config :argon2_elixir,
  t_cost: 1,
  m_cost: 8

# File storage for tests — use a tmp directory
config :cairn, Cairn.Storage.LocalBackend, root: Path.expand("tmp/test_uploads")

# Use Oban testing mode in tests
config :cairn, Oban, testing: :inline

# Disable HTTP rate limiting in tests
config :cairn, :http_rate_limiting, false

# Disable SSL enforcement in tests
config :cairn, :force_ssl, false

# Disable PromEx in tests (pollers conflict with SQL Sandbox)
config :cairn, :start_prom_ex, false

# ALTCHA proof-of-work config for tests
config :cairn, :altcha_hmac_key, "test_altcha_hmac_key"
config :cairn, :require_pow, false
