defmodule Cairn.NotificationsTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Notifications, Servers}
  alias Cairn.Chat

  @valid_password "secure_password_123"

  defp create_user(username) do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "#{username}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  test "upsert and get global preference" do
    user = create_user("notifuser")

    {:ok, pref} =
      Notifications.upsert_preference(%{
        user_id: user.id,
        level: "mentions"
      })

    assert pref.level == "mentions"

    fetched = Notifications.get_preference(user.id)
    assert fetched.id == pref.id
  end

  test "upsert server-specific preference" do
    user = create_user("notifserver")
    {:ok, server} = Servers.create_server(%{name: "Notif Server", creator_id: user.id})

    {:ok, pref} =
      Notifications.upsert_preference(%{
        user_id: user.id,
        server_id: server.id,
        level: "nothing"
      })

    assert pref.level == "nothing"
    assert pref.server_id == server.id
  end

  test "effective_level falls through channel → server → global" do
    user = create_user("notiflevel")
    {:ok, server} = Servers.create_server(%{name: "Level Server", creator_id: user.id})
    {:ok, channel} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

    # Set server level to mentions
    {:ok, _} =
      Notifications.upsert_preference(%{
        user_id: user.id,
        server_id: server.id,
        level: "mentions"
      })

    # Channel-specific not set, should fall through to server
    assert Notifications.effective_level(user.id, server.id, channel.id) == "mentions"

    # Now set channel-specific to nothing
    {:ok, _} =
      Notifications.upsert_preference(%{
        user_id: user.id,
        server_id: server.id,
        channel_id: channel.id,
        level: "nothing"
      })

    assert Notifications.effective_level(user.id, server.id, channel.id) == "nothing"
  end

  test "DND overrides level to nothing" do
    user = create_user("notifdnd")
    {:ok, server} = Servers.create_server(%{name: "DND Server", creator_id: user.id})
    {:ok, channel} = Chat.create_channel(%{name: "general", type: "public", server_id: server.id})

    {:ok, _} =
      Notifications.upsert_preference(%{
        user_id: user.id,
        level: "all",
        dnd_enabled: true
      })

    assert Notifications.effective_level(user.id, server.id, channel.id) == "nothing"
  end

  test "get_preferences returns all user preferences" do
    user = create_user("notifprefs")
    {:ok, server} = Servers.create_server(%{name: "Pref Server", creator_id: user.id})

    {:ok, _} = Notifications.upsert_preference(%{user_id: user.id, level: "all"})

    {:ok, _} =
      Notifications.upsert_preference(%{
        user_id: user.id,
        server_id: server.id,
        level: "mentions"
      })

    prefs = Notifications.get_preferences(user.id)
    assert length(prefs) == 2
  end
end
