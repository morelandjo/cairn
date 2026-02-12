defmodule Cairn.Repo.Migrations.BackfillDefaultServer do
  use Ecto.Migration

  defp uuid_to_bin(uuid_string) do
    {:ok, bin} = Ecto.UUID.dump(uuid_string)
    bin
  end

  def up do
    # Find the first user to be the creator, or skip if no users exist
    %{rows: rows} = repo().query!("SELECT id::text FROM users LIMIT 1")

    if rows != [] do
      [[creator_uuid]] = rows
      server_id = Ecto.UUID.generate()
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      everyone_role_id = Ecto.UUID.generate()
      owner_role_id = Ecto.UUID.generate()

      sid = uuid_to_bin(server_id)
      cid = uuid_to_bin(creator_uuid)

      # Create the default server
      repo().query!(
        "INSERT INTO servers (id, name, description, creator_id, inserted_at, updated_at) VALUES ($1, 'Default Server', 'Auto-created during migration', $2, $3, $3)",
        [sid, cid, now]
      )

      # Backfill existing roles (assign them to the server first)
      repo().query!("UPDATE roles SET server_id = $1 WHERE server_id IS NULL", [sid])

      # Backfill channels (non-DM)
      repo().query!(
        "UPDATE channels SET server_id = $1 WHERE type != 'dm' AND server_id IS NULL",
        [sid]
      )

      # Backfill invite_links
      repo().query!("UPDATE invite_links SET server_id = $1 WHERE server_id IS NULL", [sid])

      # Create default roles only if they don't already exist
      for {name, permissions, priority, id} <- [
            {"@everyone",
             ~s({"send_messages": true, "read_messages": true, "attach_files": true, "use_voice": true}),
             0, everyone_role_id},
            {"Moderator",
             ~s({"send_messages": true, "read_messages": true, "manage_messages": true, "kick_members": true, "mute_members": true, "deafen_members": true, "move_members": true, "attach_files": true, "use_voice": true}),
             50, Ecto.UUID.generate()},
            {"Admin",
             ~s({"send_messages": true, "read_messages": true, "manage_messages": true, "manage_channels": true, "manage_roles": true, "kick_members": true, "ban_members": true, "invite_members": true, "manage_webhooks": true, "attach_files": true, "use_voice": true, "mute_members": true, "deafen_members": true, "move_members": true}),
             90, Ecto.UUID.generate()},
            {"Owner",
             ~s({"send_messages": true, "read_messages": true, "manage_messages": true, "manage_channels": true, "manage_roles": true, "manage_server": true, "kick_members": true, "ban_members": true, "invite_members": true, "manage_webhooks": true, "attach_files": true, "use_voice": true, "mute_members": true, "deafen_members": true, "move_members": true}),
             100, owner_role_id}
          ] do
        repo().query!(
          "INSERT INTO roles (id, server_id, name, permissions, priority, inserted_at, updated_at) VALUES ($1, $2, $3, $4::jsonb, $5, $6, $6) ON CONFLICT (server_id, name) DO UPDATE SET permissions = EXCLUDED.permissions, priority = EXCLUDED.priority, updated_at = EXCLUDED.updated_at",
          [uuid_to_bin(id), sid, name, permissions, priority, now]
        )
      end

      # Get the actual @everyone role id
      %{rows: [[actual_everyone_id]]} =
        repo().query!(
          "SELECT id FROM roles WHERE server_id = $1 AND name = '@everyone' LIMIT 1",
          [sid]
        )

      # Get the actual Owner role id
      %{rows: [[actual_owner_id]]} =
        repo().query!(
          "SELECT id FROM roles WHERE server_id = $1 AND name = 'Owner' LIMIT 1",
          [sid]
        )

      # Create server_members for all distinct users who are channel members in this server
      repo().query!(
        "INSERT INTO server_members (id, server_id, user_id, role_id, inserted_at, updated_at) SELECT gen_random_uuid(), $1, sub.user_id, $2, $3, $3 FROM (SELECT DISTINCT cm.user_id FROM channel_members cm JOIN channels c ON c.id = cm.channel_id WHERE c.server_id = $1) sub ON CONFLICT (server_id, user_id) DO NOTHING",
        [sid, actual_everyone_id, now]
      )

      # Make the creator an owner
      repo().query!(
        "INSERT INTO server_members (id, server_id, user_id, role_id, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, $3, $4, $4) ON CONFLICT (server_id, user_id) DO UPDATE SET role_id = $3",
        [sid, cid, actual_owner_id, now]
      )
    end

    # Add CHECK constraint: DM channels must have NULL server_id, non-DM must have server_id
    create constraint(:channels, :channels_server_id_type_check,
             check: "(type = 'dm' AND server_id IS NULL) OR (type != 'dm')"
           )
  end

  def down do
    drop constraint(:channels, :channels_server_id_type_check)

    execute "UPDATE channels SET server_id = NULL"
    execute "UPDATE invite_links SET server_id = NULL"
    execute "DELETE FROM server_members"

    execute "DELETE FROM roles WHERE name IN ('@everyone', 'Moderator', 'Admin', 'Owner') AND server_id IS NOT NULL"

    execute "DELETE FROM servers WHERE name = 'Default Server'"
  end
end
