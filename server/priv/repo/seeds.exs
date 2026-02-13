alias Cairn.Repo
alias Cairn.Accounts.{User, Role}
alias Cairn.Chat.{Channel, ChannelMember}
import Ecto.Query

# Create @everyone role (idempotent)
everyone_role =
  case Repo.get_by(Role, name: "@everyone") do
    nil ->
      %Role{}
      |> Role.changeset(%{
        name: "@everyone",
        permissions: %{
          "send_messages" => true,
          "read_messages" => true,
          "create_invite" => true,
          "upload_files" => true
        },
        priority: 0,
        color: "#99AAB5"
      })
      |> Repo.insert!()

    existing ->
      existing
  end

IO.puts("Role: #{everyone_role.name}")

# Create admin user (idempotent)
admin =
  case Repo.get_by(User, username: "admin") do
    nil ->
      %User{}
      |> User.registration_changeset(%{
        username: "admin",
        display_name: "Admin",
        password: "admin_password_change_me"
      })
      |> Repo.insert!()

    existing ->
      existing
  end

IO.puts("User: #{admin.username}")

# Create #general channel (idempotent)
general =
  case Repo.one(from c in Channel, where: c.name == "general" and c.type == "public") do
    nil ->
      %Channel{}
      |> Channel.changeset(%{
        name: "general",
        type: "public",
        description: "General discussion"
      })
      |> Repo.insert!()

    existing ->
      existing
  end

IO.puts("Channel: ##{general.name}")

# Add admin to #general as owner (idempotent)
unless Repo.get_by(ChannelMember, channel_id: general.id, user_id: admin.id) do
  %ChannelMember{}
  |> ChannelMember.changeset(%{
    channel_id: general.id,
    user_id: admin.id,
    role: "owner"
  })
  |> Repo.insert!()
end

IO.puts("Seeds complete!")
