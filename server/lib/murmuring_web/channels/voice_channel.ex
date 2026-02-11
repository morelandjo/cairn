defmodule MurmuringWeb.VoiceChannel do
  use MurmuringWeb, :channel

  alias Murmuring.{Chat, Voice, Moderation, RateLimiter}
  alias Murmuring.Servers.Permissions

  defp sfu_client do
    Application.get_env(:murmuring, :sfu_client, Murmuring.Voice.SfuClient)
  end

  @impl true
  def join("voice:" <> channel_id, _params, socket) do
    user_id = socket.assigns.user_id

    case Chat.get_channel(channel_id) do
      nil ->
        {:error, %{reason: "channel not found"}}

      channel ->
        cond do
          channel.type != "voice" ->
            {:error, %{reason: "not a voice channel"}}

          not has_voice_permission?(channel, user_id) ->
            {:error, %{reason: "insufficient permissions"}}

          true ->
            case setup_voice(channel, user_id) do
              {:ok, response} ->
                send(self(), :after_join)

                socket =
                  socket
                  |> assign(:channel_id, channel_id)
                  |> assign(:server_id, channel.server_id)

                {:ok, response, socket}

              {:error, %{reason: "channel_full"}} ->
                {:error, %{reason: "channel_full"}}

              {:error, _reason} ->
                {:error, %{reason: "failed to setup voice"}}
            end
        end
    end
  end

  defp has_voice_permission?(channel, user_id) do
    if channel.server_id do
      Permissions.has_channel_permission?(channel.server_id, user_id, channel.id, "use_voice")
    else
      true
    end
  end

  defp setup_voice(channel, user_id) do
    bypass_capacity =
      if channel.server_id do
        Permissions.has_permission?(channel.server_id, user_id, "manage_channels")
      else
        false
      end

    with {:ok, _room} <- sfu_client().create_room(channel.id),
         {:ok, _peer} <- sfu_client().add_peer(channel.id, user_id),
         {:ok, rtp_capabilities} <- sfu_client().get_rtp_capabilities(channel.id),
         {:ok, send_transport} <- sfu_client().create_send_transport(channel.id, user_id),
         {:ok, recv_transport} <- sfu_client().create_recv_transport(channel.id, user_id),
         {:ok, voice_state} <-
           Voice.join_voice(channel.id, user_id, channel.server_id,
             bypass_capacity: bypass_capacity
           ) do
      {:ok,
       %{
         rtpCapabilities: rtp_capabilities,
         sendTransport: send_transport,
         recvTransport: recv_transport,
         voiceState: serialize_voice_state(voice_state),
         peers: list_existing_peers(channel.id, user_id)
       }}
    end
  end

  defp list_existing_peers(channel_id, exclude_user_id) do
    Voice.list_voice_states(channel_id)
    |> Enum.reject(&(&1.user_id == exclude_user_id))
    |> Enum.map(&serialize_voice_state/1)
  end

  defp serialize_voice_state(vs) do
    %{
      userId: vs.user_id,
      channelId: vs.channel_id,
      muted: vs.muted,
      deafened: vs.deafened,
      videoOn: vs.video_on,
      screenSharing: vs.screen_sharing
    }
  end

  @impl true
  def handle_info(:after_join, socket) do
    broadcast_from!(socket, "peer_joined", %{
      userId: socket.assigns.user_id
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in(
        "connect_transport",
        %{"transportId" => transport_id, "dtlsParameters" => dtls_params},
        socket
      ) do
    channel_id = socket.assigns.channel_id

    case sfu_client().connect_transport(channel_id, transport_id, dtls_params) do
      {:ok, _} -> {:reply, :ok, socket}
      {:error, _} -> {:reply, {:error, %{reason: "transport_connect_failed"}}, socket}
    end
  end

  @impl true
  def handle_in("produce", %{"kind" => kind, "rtpParameters" => rtp_params} = payload, socket) do
    channel_id = socket.assigns.channel_id
    user_id = socket.assigns.user_id

    app_data = Map.get(payload, "appData", %{})

    case sfu_client().produce(channel_id, user_id, %{
           kind: kind,
           rtpParameters: rtp_params,
           appData: app_data
         }) do
      {:ok, %{"id" => producer_id} = result} ->
        broadcast_from!(socket, "new_producer", %{
          producerId: producer_id,
          userId: user_id,
          kind: kind,
          appData: app_data
        })

        {:reply, {:ok, result}, socket}

      {:error, _} ->
        {:reply, {:error, %{reason: "produce_failed"}}, socket}
    end
  end

  @impl true
  def handle_in("consume", %{"producerId" => producer_id, "rtpCapabilities" => rtp_caps}, socket) do
    channel_id = socket.assigns.channel_id
    user_id = socket.assigns.user_id

    case sfu_client().consume(channel_id, %{
           consumerUserId: user_id,
           producerId: producer_id,
           rtpCapabilities: rtp_caps
         }) do
      {:ok, result} -> {:reply, {:ok, result}, socket}
      {:error, _} -> {:reply, {:error, %{reason: "consume_failed"}}, socket}
    end
  end

  @impl true
  def handle_in("resume_consumer", %{"consumerId" => consumer_id}, socket) do
    channel_id = socket.assigns.channel_id

    case sfu_client().resume_consumer(channel_id, consumer_id) do
      {:ok, _} -> {:reply, :ok, socket}
      {:error, _} -> {:reply, {:error, %{reason: "resume_failed"}}, socket}
    end
  end

  @impl true
  def handle_in("update_state", attrs, socket) do
    channel_id = socket.assigns.channel_id
    user_id = socket.assigns.user_id

    allowed = Map.take(attrs, ["muted", "deafened", "videoOn", "screenSharing"])

    db_attrs =
      allowed
      |> Enum.map(fn
        {"videoOn", v} -> {:video_on, v}
        {"screenSharing", v} -> {:screen_sharing, v}
        {k, v} -> {String.to_existing_atom(k), v}
      end)
      |> Map.new()

    case Voice.update_voice_state(channel_id, user_id, db_attrs) do
      {:ok, vs} ->
        broadcast!(socket, "state_updated", serialize_voice_state(vs))
        {:reply, :ok, socket}

      {:error, _} ->
        {:reply, {:error, %{reason: "update_failed"}}, socket}
    end
  end

  @impl true
  def handle_in("speaking", %{"speaking" => speaking}, socket) do
    user_id = socket.assigns.user_id

    case RateLimiter.check(:speaking, user_id) do
      :ok ->
        broadcast_from!(socket, "speaking", %{userId: user_id, speaking: speaking})
        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_in("mod_mute", %{"userId" => target_user_id}, socket) do
    channel_id = socket.assigns.channel_id
    server_id = socket.assigns.server_id
    mod_user_id = socket.assigns.user_id

    if server_id && Permissions.has_permission?(server_id, mod_user_id, "mute_members") do
      # Pause the user's audio producer on the SFU
      case sfu_client().list_producers(channel_id, nil) do
        {:ok, producers} ->
          producers
          |> Enum.filter(&(&1["userId"] == target_user_id && &1["kind"] == "audio"))
          |> Enum.each(fn p ->
            sfu_client().producer_action(channel_id, p["producerId"], "pause")
          end)

        _ ->
          :ok
      end

      Voice.update_voice_state(channel_id, target_user_id, %{muted: true})

      Moderation.log_action(server_id, mod_user_id, "voice_mute", %{
        target_user_id: target_user_id,
        channel_id: channel_id
      })

      broadcast!(socket, "mod_muted", %{userId: target_user_id, by: mod_user_id})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "insufficient permissions"}}, socket}
    end
  end

  @impl true
  def handle_in("mod_disconnect", %{"userId" => target_user_id}, socket) do
    channel_id = socket.assigns.channel_id
    server_id = socket.assigns.server_id
    mod_user_id = socket.assigns.user_id

    if server_id && Permissions.has_permission?(server_id, mod_user_id, "kick_members") do
      cleanup_peer(channel_id, target_user_id)

      Moderation.log_action(server_id, mod_user_id, "voice_disconnect", %{
        target_user_id: target_user_id,
        channel_id: channel_id
      })

      broadcast!(socket, "peer_disconnected", %{userId: target_user_id, by: mod_user_id})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "insufficient permissions"}}, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if Map.has_key?(socket.assigns, :channel_id) do
      channel_id = socket.assigns.channel_id
      user_id = socket.assigns.user_id
      cleanup_peer(channel_id, user_id)
      broadcast!(socket, "peer_left", %{userId: user_id})
    end

    :ok
  end

  defp cleanup_peer(channel_id, user_id) do
    sfu_client().remove_peer(channel_id, user_id)
    Voice.leave_voice(channel_id, user_id)
  end
end
