defmodule MurmuringWeb.Router do
  use MurmuringWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug MurmuringWeb.Plugs.RateLimiter
  end

  pipeline :authenticated do
    plug MurmuringWeb.Plugs.Auth
  end

  pipeline :admin do
    plug MurmuringWeb.Plugs.AdminAuth
  end

  pipeline :federated do
    plug MurmuringWeb.Plugs.FederatedAuth
  end

  scope "/", MurmuringWeb do
    get "/health", HealthController, :index
  end

  # Prometheus metrics endpoint
  scope "/" do
    get "/metrics", PromEx.Plug, prom_ex_module: Murmuring.PromEx
  end

  # Well-known federation endpoints (no auth required)
  scope "/.well-known", MurmuringWeb do
    pipe_through :api

    get "/murmuring-federation", FederationController, :federation_info
    get "/privacy-manifest", FederationController, :privacy_manifest
    get "/webfinger", FederationController, :webfinger
    get "/did/:did", FederationController, :resolve_did
    get "/did/:did/operations", FederationController, :did_operations
  end

  # Federation inbox (verified by HTTP signatures, no user auth)
  scope "/", MurmuringWeb do
    pipe_through :api

    post "/inbox", InboxController, :create
  end

  # Federation node-to-node endpoints (no user auth, verified by HTTP signatures)
  scope "/api/v1/federation", MurmuringWeb do
    pipe_through :api

    get "/users/:did/keys", FederationController, :user_keys_by_did
  end

  # ActivityPub actor profiles (public, no auth required)
  scope "/users", MurmuringWeb do
    pipe_through :api

    get "/:username", ActorController, :show
    get "/:username/outbox", ActorController, :outbox
  end

  scope "/api/v1", MurmuringWeb do
    pipe_through :api

    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
    post "/auth/refresh", AuthController, :refresh
    post "/auth/recover", AuthController, :recover

    post "/auth/totp/authenticate", TotpController, :authenticate

    # Webhook execution (token IS auth, no user auth needed)
    post "/webhooks/:token", WebhookController, :execute
  end

  scope "/api/v1", MurmuringWeb do
    pipe_through [:api, :authenticated]

    get "/auth/me", AuthController, :me

    post "/auth/totp/enable", TotpController, :enable
    post "/auth/totp/verify", TotpController, :verify
    post "/auth/totp/disable", TotpController, :disable

    post "/auth/webauthn/register", WebauthnController, :register
    post "/auth/webauthn/register/complete", WebauthnController, :register_complete
    post "/auth/webauthn/authenticate", WebauthnController, :authenticate
    post "/auth/webauthn/authenticate/complete", WebauthnController, :authenticate_complete

    post "/users/me/keys", KeyController, :upload
    get "/users/me/keys/prekey-count", KeyController, :prekey_count
    get "/users/:user_id/keys", KeyController, :show

    post "/users/me/key-packages", KeyController, :upload_key_packages
    get "/users/me/key-packages/count", KeyController, :key_package_count
    get "/users/:user_id/key-packages", KeyController, :claim_key_package

    post "/users/me/key-backup", KeyController, :upload_backup
    get "/users/me/key-backup", KeyController, :download_backup
    delete "/users/me/key-backup", KeyController, :delete_backup

    # DID identity operations
    post "/users/me/did/rotate-signing-key", KeyController, :rotate_signing_key

    # Server CRUD
    get "/servers", ServerController, :index
    post "/servers", ServerController, :create
    get "/servers/:id", ServerController, :show
    put "/servers/:id", ServerController, :update
    delete "/servers/:id", ServerController, :delete

    # Server membership
    get "/servers/:server_id/members", ServerController, :members
    post "/servers/:server_id/join", ServerController, :join
    post "/servers/:server_id/leave", ServerController, :leave

    # Server-scoped channels
    get "/servers/:server_id/channels", ServerController, :channels
    post "/servers/:server_id/channels", ServerController, :create_channel

    # Server-scoped roles
    get "/servers/:server_id/roles", ServerController, :roles
    post "/servers/:server_id/roles", ServerController, :create_role
    put "/servers/:server_id/roles/:role_id", ServerController, :update_role
    delete "/servers/:server_id/roles/:role_id", ServerController, :delete_role

    # Channel categories
    get "/servers/:server_id/categories", ServerController, :list_categories
    post "/servers/:server_id/categories", ServerController, :create_category
    put "/servers/:server_id/categories/:category_id", ServerController, :update_category
    delete "/servers/:server_id/categories/:category_id", ServerController, :delete_category
    put "/servers/:server_id/channels/reorder", ServerController, :reorder_channels

    # Pinned messages
    get "/channels/:id/pins", ChannelController, :list_pins
    post "/channels/:id/pins", ChannelController, :pin_message
    delete "/channels/:id/pins/:message_id", ChannelController, :unpin_message

    # Webhooks (authenticated management endpoints)
    get "/servers/:server_id/webhooks", WebhookController, :index
    post "/servers/:server_id/webhooks", WebhookController, :create
    delete "/servers/:server_id/webhooks/:wid", WebhookController, :delete

    post "/servers/:server_id/webhooks/:wid/regenerate-token",
         WebhookController,
         :regenerate_token

    # Bot accounts
    post "/servers/:server_id/bots", BotController, :create
    get "/servers/:server_id/bots", BotController, :index
    delete "/servers/:server_id/bots/:bid", BotController, :delete
    put "/servers/:server_id/bots/:bid/channels", BotController, :update_channels
    post "/servers/:server_id/bots/:bid/regenerate-token", BotController, :regenerate_token

    # Custom emojis
    get "/servers/:server_id/emojis", EmojiController, :index
    post "/servers/:server_id/emojis", EmojiController, :create
    delete "/servers/:server_id/emojis/:emoji_id", EmojiController, :delete

    # Search
    get "/servers/:server_id/search", SearchController, :search

    # Reports
    post "/messages/:message_id/report", ModerationController, :report_message
    get "/servers/:server_id/reports", ModerationController, :list_reports
    put "/servers/:server_id/reports/:report_id", ModerationController, :resolve_report

    # Slow mode
    put "/channels/:id/slow-mode", ChannelController, :set_slow_mode

    # Auto-mod rules
    get "/servers/:server_id/auto-mod-rules", ModerationController, :list_auto_mod_rules
    post "/servers/:server_id/auto-mod-rules", ModerationController, :create_auto_mod_rule
    put "/servers/:server_id/auto-mod-rules/:rule_id", ModerationController, :update_auto_mod_rule

    delete "/servers/:server_id/auto-mod-rules/:rule_id",
           ModerationController,
           :delete_auto_mod_rule

    # Moderation
    post "/servers/:server_id/mutes", ModerationController, :mute
    delete "/servers/:server_id/mutes/:user_id", ModerationController, :unmute
    get "/servers/:server_id/mutes", ModerationController, :list_mutes
    post "/servers/:server_id/kicks/:user_id", ModerationController, :kick
    post "/servers/:server_id/bans", ModerationController, :ban
    delete "/servers/:server_id/bans/:user_id", ModerationController, :unban
    get "/servers/:server_id/bans", ModerationController, :list_bans
    get "/servers/:server_id/moderation-log", ModerationController, :mod_log

    # Threading and reactions
    get "/channels/:id/messages/:message_id/thread", ChannelController, :thread
    get "/channels/:id/messages/:message_id/reactions", ChannelController, :list_reactions
    post "/channels/:id/messages/:message_id/reactions", ChannelController, :add_reaction

    delete "/channels/:id/messages/:message_id/reactions/:emoji",
           ChannelController,
           :remove_reaction

    # Channel permission overrides
    put "/servers/:id/channels/:cid/overrides/role/:role_id", ServerController, :set_role_override

    delete "/servers/:id/channels/:cid/overrides/role/:role_id",
           ServerController,
           :delete_role_override

    put "/servers/:id/channels/:cid/overrides/user/:user_id", ServerController, :set_user_override

    delete "/servers/:id/channels/:cid/overrides/user/:user_id",
           ServerController,
           :delete_user_override

    get "/servers/:id/channels/:cid/overrides", ServerController, :list_overrides

    # Multi-role management
    post "/servers/:id/members/:uid/roles/:role_id", ServerController, :add_member_role
    delete "/servers/:id/members/:uid/roles/:role_id", ServerController, :remove_member_role

    # Backward-compatible flat channel routes
    get "/channels", ChannelController, :index
    post "/channels", ChannelController, :create
    get "/channels/:id", ChannelController, :show
    get "/channels/:id/messages", ChannelController, :messages
    get "/channels/:id/members", ChannelController, :members

    # MLS delivery endpoints
    post "/channels/:id/mls/group-info", MlsController, :store_group_info
    get "/channels/:id/mls/group-info", MlsController, :get_group_info
    post "/channels/:id/mls/commit", MlsController, :store_commit
    post "/channels/:id/mls/proposal", MlsController, :store_proposal
    post "/channels/:id/mls/welcome", MlsController, :store_welcome
    get "/channels/:id/mls/messages", MlsController, :pending_messages
    post "/channels/:id/mls/ack", MlsController, :ack_messages

    post "/invites", InviteController, :create
    get "/invites/:code", InviteController, :show
    post "/invites/:code/use", InviteController, :use

    post "/upload", UploadController, :create
    get "/files/:id", UploadController, :show
    get "/files/:id/thumbnail", UploadController, :thumbnail

    # Notification preferences
    get "/users/me/notification-preferences", NotificationController, :index
    put "/users/me/notification-preferences", NotificationController, :update

    # Push notification tokens
    post "/users/me/push-tokens", PushTokenController, :create
    delete "/users/me/push-tokens/:token", PushTokenController, :delete

    # Server discovery (listing/unlisting requires manage_server)
    get "/directory", DiscoveryController, :index
    post "/servers/:server_id/directory/list", DiscoveryController, :list
    delete "/servers/:server_id/directory/unlist", DiscoveryController, :unlist

    # Voice / TURN
    get "/voice/turn-credentials", VoiceController, :turn_credentials
    get "/voice/ice-servers", VoiceController, :ice_servers

    # Data export
    post "/users/me/export", ExportController, :create
    get "/users/me/export/download", ExportController, :download
    post "/users/me/export/portability", ExportController, :portability

    # Federated auth token issuance (local user → token for remote instance)
    post "/federation/auth-token", FederatedAuthController, :issue_token

    # Cross-instance DM endpoints
    post "/dm/federated", DmController, :create_federated_dm
    get "/dm/requests", DmController, :list_dm_requests
    get "/dm/requests/sent", DmController, :list_sent_dm_requests
    post "/dm/requests/:id/respond", DmController, :respond_to_dm_request
    post "/dm/requests/:id/block", DmController, :block_sender
  end

  # Federated routes (authenticated via FederatedToken, not JWT)
  scope "/api/v1/federated", MurmuringWeb do
    pipe_through [:api, :federated]

    post "/join/:server_id", FederatedAuthController, :join_server
    get "/servers/:id/channels", FederatedAuthController, :server_channels
    post "/invites/:code/use", FederatedAuthController, :use_invite
  end

  # Admin endpoints (require auth + admin privileges)
  scope "/api/v1/admin", MurmuringWeb.Admin do
    pipe_through [:api, :authenticated, :admin]

    get "/federation/nodes", FederationController, :index
    post "/federation/nodes", FederationController, :create
    get "/federation/nodes/:id", FederationController, :show
    post "/federation/nodes/:id/block", FederationController, :block
    post "/federation/nodes/:id/unblock", FederationController, :unblock
    delete "/federation/nodes/:id", FederationController, :delete
    get "/federation/activities", FederationController, :activities
    post "/federation/rotate-key", FederationController, :rotate_key
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:murmuring, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: MurmuringWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # SPA catch-all — serves the web client for any unmatched GET request.
  # Must be last so API routes take priority.
  if Application.compile_env(:murmuring, :serve_spa, false) do
    scope "/", MurmuringWeb do
      get "/*path", SpaController, :index
    end
  end
end
