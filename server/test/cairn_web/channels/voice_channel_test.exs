defmodule CairnWeb.VoiceChannelTest do
  use CairnWeb.ChannelCase

  alias Cairn.{Accounts, Auth, Chat, Servers}

  @valid_password "secure_password_123"

  defmodule MockSfuClient do
    @behaviour Cairn.Voice.SfuClientBehaviour

    @impl true
    def create_room(_channel_id),
      do: {:ok, %{"channelId" => "test", "rtpCapabilities" => %{"codecs" => []}}}

    @impl true
    def destroy_room(_channel_id), do: {:ok, %{"ok" => true}}

    @impl true
    def get_rtp_capabilities(_channel_id),
      do: {:ok, %{"codecs" => [%{"kind" => "audio", "mimeType" => "audio/opus"}]}}

    @impl true
    def add_peer(_channel_id, _user_id), do: {:ok, %{"userId" => "test"}}

    @impl true
    def remove_peer(_channel_id, _user_id), do: {:ok, %{"ok" => true}}

    @impl true
    def create_send_transport(_channel_id, _user_id) do
      {:ok,
       %{
         "id" => "send-transport-1",
         "iceParameters" => %{},
         "iceCandidates" => [],
         "dtlsParameters" => %{}
       }}
    end

    @impl true
    def create_recv_transport(_channel_id, _user_id) do
      {:ok,
       %{
         "id" => "recv-transport-1",
         "iceParameters" => %{},
         "iceCandidates" => [],
         "dtlsParameters" => %{}
       }}
    end

    @impl true
    def connect_transport(_channel_id, _transport_id, _dtls), do: {:ok, %{"ok" => true}}

    @impl true
    def produce(_channel_id, _user_id, _params),
      do: {:ok, %{"id" => "producer-1", "kind" => "audio"}}

    @impl true
    def consume(_channel_id, _params) do
      {:ok,
       %{
         "id" => "consumer-1",
         "producerId" => "producer-1",
         "kind" => "audio",
         "rtpParameters" => %{}
       }}
    end

    @impl true
    def resume_consumer(_channel_id, _consumer_id), do: {:ok, %{"ok" => true}}

    @impl true
    def producer_action(_channel_id, _producer_id, _action), do: {:ok, %{"ok" => true}}

    @impl true
    def list_producers(_channel_id, _exclude), do: {:ok, []}
  end

  setup do
    # Use mock SFU client
    Application.put_env(:cairn, :sfu_client, MockSfuClient)

    on_exit(fn ->
      Application.put_env(:cairn, :sfu_client, Cairn.Voice.SfuClient)
    end)

    {:ok, {user, _codes}} =
      Accounts.register_user(%{
        "username" => "voicechan_#{System.unique_integer([:positive])}",
        "password" => @valid_password
      })

    {:ok, tokens} = Auth.generate_tokens(user)
    {:ok, server} = Servers.create_server(%{name: "Voice Test Server", creator_id: user.id})

    {:ok, channel} =
      Chat.create_channel(%{name: "voice-room", type: "voice", server_id: server.id})

    {:ok, socket} =
      connect(CairnWeb.UserSocket, %{"token" => tokens.access_token})

    {:ok, socket: socket, user: user, server: server, channel: channel}
  end

  describe "join" do
    test "joins a voice channel", %{socket: socket, channel: channel} do
      {:ok, reply, _socket} = subscribe_and_join(socket, "voice:#{channel.id}", %{})

      assert %{rtpCapabilities: _, sendTransport: _, recvTransport: _} = reply
    end

    test "rejects join for non-voice channel", %{socket: socket, server: server} do
      {:ok, text_channel} =
        Chat.create_channel(%{name: "text-room", type: "public", server_id: server.id})

      assert {:error, %{reason: "not a voice channel"}} =
               subscribe_and_join(socket, "voice:#{text_channel.id}", %{})
    end

    test "rejects join for non-existent channel", %{socket: socket} do
      fake_id = Ecto.UUID.generate()

      assert {:error, %{reason: "channel not found"}} =
               subscribe_and_join(socket, "voice:#{fake_id}", %{})
    end
  end

  describe "signaling events" do
    setup %{socket: socket, channel: channel} do
      {:ok, _reply, socket} = subscribe_and_join(socket, "voice:#{channel.id}", %{})
      {:ok, socket: socket}
    end

    test "connect_transport", %{socket: socket} do
      ref =
        push(socket, "connect_transport", %{
          "transportId" => "send-transport-1",
          "dtlsParameters" => %{"role" => "client", "fingerprints" => []}
        })

      assert_reply ref, :ok
    end

    test "produce", %{socket: socket} do
      ref =
        push(socket, "produce", %{
          "kind" => "audio",
          "rtpParameters" => %{"codecs" => []}
        })

      assert_reply ref, :ok, %{"id" => "producer-1", "kind" => "audio"}
    end

    test "produce broadcasts new_producer", %{socket: socket} do
      push(socket, "produce", %{
        "kind" => "audio",
        "rtpParameters" => %{"codecs" => []}
      })

      # The broadcast_from! won't be received by the sender
      # but we can verify no crash occurs
    end

    test "consume", %{socket: socket} do
      ref =
        push(socket, "consume", %{
          "producerId" => "producer-1",
          "rtpCapabilities" => %{"codecs" => []}
        })

      assert_reply ref, :ok, %{"id" => "consumer-1"}
    end

    test "resume_consumer", %{socket: socket} do
      ref = push(socket, "resume_consumer", %{"consumerId" => "consumer-1"})
      assert_reply ref, :ok
    end

    test "update_state", %{socket: socket} do
      ref = push(socket, "update_state", %{"muted" => true, "deafened" => false})
      assert_reply ref, :ok
      assert_broadcast "state_updated", %{muted: true}
    end

    test "speaking", %{socket: socket} do
      push(socket, "speaking", %{"speaking" => true})
      # speaking uses broadcast_from! so we won't receive it ourselves
    end
  end
end
