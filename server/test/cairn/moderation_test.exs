defmodule Murmuring.ModerationTest do
  use Murmuring.DataCase, async: true

  alias Murmuring.{Accounts, Moderation, Servers}

  @valid_password "secure_password_123"

  defp create_user(suffix) do
    {:ok, {user, _}} =
      Accounts.register_user(%{
        "username" => "moduser_#{suffix}_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    user
  end

  defp setup_server do
    owner = create_user("owner")
    member = create_user("member")
    {:ok, server} = Servers.create_server(%{name: "ModTest", creator_id: owner.id})
    {:ok, _} = Servers.add_member(server.id, member.id)
    %{owner: owner, member: member, server: server}
  end

  describe "mutes" do
    test "mute and check muted status" do
      %{owner: owner, member: member, server: server} = setup_server()

      {:ok, mute} =
        Moderation.mute_user(%{
          server_id: server.id,
          user_id: member.id,
          muted_by_id: owner.id,
          reason: "Spamming"
        })

      assert mute.reason == "Spamming"
      assert Moderation.is_muted?(server.id, member.id)
    end

    test "unmute a user" do
      %{owner: owner, member: member, server: server} = setup_server()

      {:ok, _} =
        Moderation.mute_user(%{
          server_id: server.id,
          user_id: member.id,
          muted_by_id: owner.id
        })

      assert Moderation.is_muted?(server.id, member.id)

      :ok = Moderation.unmute_user(server.id, member.id, owner.id)
      refute Moderation.is_muted?(server.id, member.id)
    end

    test "expired mute is not active" do
      %{owner: owner, member: member, server: server} = setup_server()

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      {:ok, _} =
        Moderation.mute_user(%{
          server_id: server.id,
          user_id: member.id,
          muted_by_id: owner.id,
          expires_at: past
        })

      refute Moderation.is_muted?(server.id, member.id)
    end

    test "list mutes" do
      %{owner: owner, member: member, server: server} = setup_server()

      {:ok, _} =
        Moderation.mute_user(%{
          server_id: server.id,
          user_id: member.id,
          muted_by_id: owner.id
        })

      mutes = Moderation.list_mutes(server.id)
      assert length(mutes) == 1
      assert hd(mutes).user_id == member.id
    end
  end

  describe "bans" do
    test "ban removes member from server" do
      %{owner: owner, member: member, server: server} = setup_server()

      assert Servers.is_member?(server.id, member.id)

      {:ok, ban} =
        Moderation.ban_user(%{
          server_id: server.id,
          user_id: member.id,
          banned_by_id: owner.id,
          reason: "Bad behavior"
        })

      assert ban.reason == "Bad behavior"
      assert Moderation.is_banned?(server.id, member.id)
      refute Servers.is_member?(server.id, member.id)
    end

    test "banned user cannot rejoin" do
      %{owner: owner, member: member, server: server} = setup_server()

      {:ok, _} =
        Moderation.ban_user(%{
          server_id: server.id,
          user_id: member.id,
          banned_by_id: owner.id
        })

      assert {:error, :banned} = Servers.add_member(server.id, member.id)
    end

    test "unban allows rejoin" do
      %{owner: owner, member: member, server: server} = setup_server()

      {:ok, _} =
        Moderation.ban_user(%{
          server_id: server.id,
          user_id: member.id,
          banned_by_id: owner.id
        })

      :ok = Moderation.unban_user(server.id, member.id, owner.id)
      refute Moderation.is_banned?(server.id, member.id)

      {:ok, _} = Servers.add_member(server.id, member.id)
      assert Servers.is_member?(server.id, member.id)
    end

    test "expired ban is not active" do
      %{owner: owner, member: member, server: server} = setup_server()

      past = DateTime.add(DateTime.utc_now(), -60, :second)

      {:ok, _} =
        Moderation.ban_user(%{
          server_id: server.id,
          user_id: member.id,
          banned_by_id: owner.id,
          expires_at: past
        })

      refute Moderation.is_banned?(server.id, member.id)
    end
  end

  describe "kicks" do
    test "kick removes member" do
      %{owner: owner, member: member, server: server} = setup_server()

      assert Servers.is_member?(server.id, member.id)
      :ok = Moderation.kick_user(server.id, member.id, owner.id)
      refute Servers.is_member?(server.id, member.id)
    end

    test "kicked user can rejoin" do
      %{owner: owner, member: member, server: server} = setup_server()

      :ok = Moderation.kick_user(server.id, member.id, owner.id)
      {:ok, _} = Servers.add_member(server.id, member.id)
      assert Servers.is_member?(server.id, member.id)
    end
  end

  describe "moderation log" do
    test "actions are logged" do
      %{owner: owner, member: member, server: server} = setup_server()

      {:ok, _} =
        Moderation.mute_user(%{
          server_id: server.id,
          user_id: member.id,
          muted_by_id: owner.id
        })

      :ok = Moderation.kick_user(server.id, member.id, owner.id)

      log = Moderation.list_mod_log(server.id)
      assert length(log) == 2

      actions = Enum.map(log, & &1.action)
      assert "mute" in actions
      assert "kick" in actions
    end
  end
end
