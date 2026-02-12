defmodule Cairn.Audit.AuditLog do
  @moduledoc "Schema for audit log entries."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @event_types ~w(
    auth.login auth.login_failed auth.logout auth.register
    auth.totp_enabled auth.totp_disabled auth.webauthn_added
    auth.password_changed auth.token_refreshed
    server.created server.updated server.deleted
    server.member_joined server.member_left server.member_kicked server.member_banned
    role.created role.updated role.deleted role.assigned role.removed
    channel.created channel.updated channel.deleted
    moderation.mute moderation.unmute moderation.ban moderation.unban moderation.kick
    moderation.report_created moderation.report_resolved
    federation.handshake federation.node_blocked federation.node_unblocked
    federation.key_rotated
    admin.settings_changed
  )

  schema "audit_logs" do
    field :event_type, :string
    field :actor_id, :binary_id
    field :target_id, :string
    field :target_type, :string
    field :metadata, :map, default: %{}
    field :ip_address, :string
    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:event_type, :actor_id, :target_id, :target_type, :metadata, :ip_address])
    |> validate_required([:event_type])
    |> validate_inclusion(:event_type, @event_types)
  end
end
