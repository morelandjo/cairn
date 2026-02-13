import Config

# SSL redirect is handled at runtime by CairnWeb.Plugs.RequireSsl,
# which reads `config :cairn, :force_ssl` (set via FORCE_SSL env var).
# This allows operators to disable SSL for LAN/tunnel deployments.

# Configure Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Serve web client SPA from priv/static/app/ in production
config :cairn, :serve_spa, true

# Default: SSL enforcement enabled (HSTS via SecurityHeaders plug, redirect via RequireSsl plug).
# Override at runtime with FORCE_SSL=false for LAN/tunnel deployments (federation must be disabled).
config :cairn, :force_ssl, true

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
