defmodule Cairn.VoiceTest do
  use Cairn.DataCase, async: true

  alias Cairn.{Accounts, Voice, Chat, Servers}

  @valid_password "secure_password_123"

  setup do
    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "voiceuser_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, server} = Servers.create_server(%{name: "Voice Server", creator_id: user.id})

    {:ok, channel} =
      Chat.create_channel(%{
        name: "voice-test",
        type: "voice",
        server_id: server.id
      })

    {:ok, user: user, server: server, channel: channel}
  end

  describe "join_voice/3" do
    test "joins a voice channel", %{channel: channel, user: user, server: server} do
      assert {:ok, vs} = Voice.join_voice(channel.id, user.id, server.id)
      assert vs.channel_id == channel.id
      assert vs.user_id == user.id
      assert vs.muted == false
      assert vs.deafened == false
    end

    test "idempotent join (upserts)", %{channel: channel, user: user, server: server} do
      assert {:ok, _vs1} = Voice.join_voice(channel.id, user.id, server.id)
      assert {:ok, vs2} = Voice.join_voice(channel.id, user.id, server.id)
      assert vs2.channel_id == channel.id
    end

    test "rejects when channel is full", %{channel: channel, server: server} do
      # Set max_participants to 1
      channel
      |> Ecto.Changeset.change(%{max_participants: 1})
      |> Cairn.Repo.update!()

      {:ok, {u1, _}} =
        Accounts.register_user(%{
          "username" => "full1_#{System.unique_integer([:positive])}",
          "password" => @valid_password
        })

      {:ok, {u2, _}} =
        Accounts.register_user(%{
          "username" => "full2_#{System.unique_integer([:positive])}",
          "password" => @valid_password
        })

      assert {:ok, _} = Voice.join_voice(channel.id, u1.id, server.id)
      assert {:error, %{reason: "channel_full"}} = Voice.join_voice(channel.id, u2.id, server.id)
    end
  end

  describe "leave_voice/2" do
    test "leaves a voice channel", %{channel: channel, user: user, server: server} do
      {:ok, _} = Voice.join_voice(channel.id, user.id, server.id)
      assert {:ok, _} = Voice.leave_voice(channel.id, user.id)
      assert Voice.get_voice_state(channel.id, user.id) == nil
    end

    test "returns error when not in voice", %{channel: channel, user: user} do
      assert {:error, :not_found} = Voice.leave_voice(channel.id, user.id)
    end
  end

  describe "list_voice_states/1" do
    test "lists all voice participants", %{channel: channel, server: server} do
      users =
        for i <- 1..3 do
          {:ok, {u, _}} =
            Accounts.register_user(%{
              "username" => "list_#{i}_#{System.unique_integer([:positive])}",
              "password" => @valid_password
            })

          {:ok, _} = Voice.join_voice(channel.id, u.id, server.id)
          u
        end

      states = Voice.list_voice_states(channel.id)
      assert length(states) == 3
    end
  end

  describe "update_voice_state/3" do
    test "updates muted/deafened state", %{channel: channel, user: user, server: server} do
      {:ok, _} = Voice.join_voice(channel.id, user.id, server.id)

      assert {:ok, vs} =
               Voice.update_voice_state(channel.id, user.id, %{muted: true, deafened: true})

      assert vs.muted == true
      assert vs.deafened == true
    end

    test "updates video/screensharing state", %{channel: channel, user: user, server: server} do
      {:ok, _} = Voice.join_voice(channel.id, user.id, server.id)

      assert {:ok, vs} =
               Voice.update_voice_state(channel.id, user.id, %{
                 video_on: true,
                 screen_sharing: true
               })

      assert vs.video_on == true
      assert vs.screen_sharing == true
    end
  end

  describe "count_participants/1" do
    test "counts participants in a channel", %{channel: channel, server: server} do
      assert Voice.count_participants(channel.id) == 0

      {:ok, {u1, _}} =
        Accounts.register_user(%{
          "username" => "count1_#{System.unique_integer([:positive])}",
          "password" => @valid_password
        })

      {:ok, _} = Voice.join_voice(channel.id, u1.id, server.id)
      assert Voice.count_participants(channel.id) == 1
    end
  end

  describe "cleanup_user/1" do
    test "removes all voice states for a user", %{channel: channel, user: user, server: server} do
      {:ok, _} = Voice.join_voice(channel.id, user.id, server.id)
      assert {1, _} = Voice.cleanup_user(user.id)
      assert Voice.get_voice_state(channel.id, user.id) == nil
    end
  end
end
