defmodule Cairn.Repo.Migrations.CreatePhase4Tables do
  use Ecto.Migration

  def change do
    # ── Multi-role join table ──────────────────────────────────────────
    create table(:server_member_roles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :server_member_id,
          references(:server_members, type: :binary_id, on_delete: :delete_all), null: false

      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:server_member_roles, [:server_member_id, :role_id])
    create index(:server_member_roles, [:role_id])

    # ── Channel permission overrides ───────────────────────────────────
    create table(:channel_permission_overrides, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :permissions, :map, default: %{}, null: false
      timestamps()
    end

    create index(:channel_permission_overrides, [:channel_id])

    create unique_index(:channel_permission_overrides, [:channel_id, :role_id],
             where: "role_id IS NOT NULL",
             name: :channel_permission_overrides_channel_role_idx
           )

    create unique_index(:channel_permission_overrides, [:channel_id, :user_id],
             where: "user_id IS NOT NULL",
             name: :channel_permission_overrides_channel_user_idx
           )

    # Constraint: exactly one of role_id/user_id must be non-null
    create constraint(:channel_permission_overrides, :role_or_user_required,
             check:
               "(role_id IS NOT NULL AND user_id IS NULL) OR (role_id IS NULL AND user_id IS NOT NULL)"
           )

    # ── Channel categories ─────────────────────────────────────────────
    create table(:channel_categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, size: 100, null: false
      add :position, :integer, default: 0, null: false
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:channel_categories, [:server_id])

    # ── Alter channels: add category_id, position, slow_mode_seconds ──
    alter table(:channels) do
      add :category_id, references(:channel_categories, type: :binary_id, on_delete: :nilify_all)
      add :position, :integer, default: 0, null: false
      add :slow_mode_seconds, :integer, default: 0, null: false
    end

    # ── Alter messages: add reply_to_id ────────────────────────────────
    alter table(:messages) do
      add :reply_to_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:messages, [:reply_to_id])

    # ── Alter users: add is_bot ────────────────────────────────────────
    alter table(:users) do
      add :is_bot, :boolean, default: false, null: false
    end

    # ── Pinned messages ────────────────────────────────────────────────
    create table(:pinned_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :pinned_by_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      timestamps()
    end

    create unique_index(:pinned_messages, [:channel_id, :message_id])
    create index(:pinned_messages, [:channel_id])

    # ── Reactions ──────────────────────────────────────────────────────
    create table(:reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :emoji, :string, size: 64, null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:reactions, [:message_id, :user_id, :emoji])
    create index(:reactions, [:message_id])

    # ── Server mutes ──────────────────────────────────────────────────
    create table(:server_mutes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason, :string
      add :expires_at, :utc_datetime
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all)
      add :muted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      timestamps()
    end

    create index(:server_mutes, [:server_id, :user_id])

    # ── Server bans ───────────────────────────────────────────────────
    create table(:server_bans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason, :string
      add :expires_at, :utc_datetime
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :banned_by_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      timestamps()
    end

    create unique_index(:server_bans, [:server_id, :user_id])

    # ── Moderation log ────────────────────────────────────────────────
    create table(:moderation_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :details, :map, default: %{}
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :moderator_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :target_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :target_message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :target_channel_id, references(:channels, type: :binary_id, on_delete: :nilify_all)
      timestamps()
    end

    create index(:moderation_log, [:server_id])
    create index(:moderation_log, [:server_id, :inserted_at])

    # ── Message reports ───────────────────────────────────────────────
    create table(:message_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason, :string, null: false
      add :details, :string
      add :status, :string, default: "pending", null: false
      add :resolution_action, :string

      add :message_id, references(:messages, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :reporter_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :resolved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps()
    end

    create index(:message_reports, [:server_id, :status])

    # ── Auto-mod rules ────────────────────────────────────────────────
    create table(:auto_mod_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :rule_type, :string, null: false
      add :enabled, :boolean, default: true, null: false
      add :config, :map, default: %{}, null: false
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:auto_mod_rules, [:server_id])

    # ── Custom emojis ─────────────────────────────────────────────────
    create table(:custom_emojis, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, size: 32, null: false
      add :file_key, :string, null: false
      add :animated, :boolean, default: false, null: false
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :uploader_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      timestamps()
    end

    create unique_index(:custom_emojis, [:server_id, :name])

    # ── Webhooks ──────────────────────────────────────────────────────
    create table(:webhooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, size: 100, null: false
      add :token, :string, null: false
      add :avatar_key, :string
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :creator_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      timestamps()
    end

    create unique_index(:webhooks, [:token])

    # ── Bot accounts ──────────────────────────────────────────────────
    create table(:bot_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_token_hash, :string, null: false
      add :allowed_channels, {:array, :binary_id}, default: []
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :creator_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      timestamps()
    end

    create unique_index(:bot_accounts, [:user_id, :server_id])

    # ── Notification preferences ──────────────────────────────────────
    create table(:notification_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :level, :string, default: "all", null: false
      add :dnd_enabled, :boolean, default: false, null: false
      add :quiet_hours_start, :time
      add :quiet_hours_end, :time
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all)
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:notification_preferences, [:user_id, :server_id, :channel_id],
             name: :notification_preferences_user_scope_idx
           )

    # ── Server directory entries ──────────────────────────────────────
    create table(:server_directory_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :description, :string
      add :tags, {:array, :string}, default: []
      add :member_count, :integer, default: 0, null: false
      add :listed_at, :utc_datetime
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:server_directory_entries, [:server_id])

    # ── Link previews ─────────────────────────────────────────────────
    create table(:link_previews, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url_hash, :string, null: false
      add :url, :text, null: false
      add :title, :string
      add :description, :text
      add :image_url, :text
      add :site_name, :string
      add :expires_at, :utc_datetime, null: false
      timestamps()
    end

    create unique_index(:link_previews, [:url_hash])
  end
end
