defmodule Murmuring.Voice.SfuClient do
  @behaviour Murmuring.Voice.SfuClientBehaviour

  defp base_url do
    Application.get_env(:murmuring, :sfu_url, "http://localhost:4001")
  end

  defp auth_secret do
    Application.get_env(:murmuring, :sfu_auth_secret, "dev-sfu-secret")
  end

  defp headers do
    [{"authorization", "Bearer #{auth_secret()}"}]
  end

  defp post_json(path, body) do
    url = "#{base_url()}#{path}"

    case Req.post(url, json: body, headers: headers()) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_json(path) do
    url = "#{base_url()}#{path}"

    case Req.get(url, headers: headers()) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_json(path) do
    url = "#{base_url()}#{path}"

    case Req.delete(url, headers: headers()) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def create_room(channel_id) do
    post_json("/rooms", %{channelId: channel_id})
  end

  @impl true
  def destroy_room(channel_id) do
    delete_json("/rooms/#{channel_id}")
  end

  @impl true
  def get_rtp_capabilities(channel_id) do
    get_json("/rooms/#{channel_id}/rtp-capabilities")
  end

  @impl true
  def add_peer(channel_id, user_id) do
    post_json("/rooms/#{channel_id}/peers", %{userId: user_id})
  end

  @impl true
  def remove_peer(channel_id, user_id) do
    delete_json("/rooms/#{channel_id}/peers/#{user_id}")
  end

  @impl true
  def create_send_transport(channel_id, user_id) do
    post_json("/rooms/#{channel_id}/peers/#{user_id}/send-transport", %{})
  end

  @impl true
  def create_recv_transport(channel_id, user_id) do
    post_json("/rooms/#{channel_id}/peers/#{user_id}/recv-transport", %{})
  end

  @impl true
  def connect_transport(channel_id, transport_id, dtls_parameters) do
    post_json("/rooms/#{channel_id}/transports/#{transport_id}/connect", %{
      dtlsParameters: dtls_parameters
    })
  end

  @impl true
  def produce(channel_id, user_id, params) do
    post_json("/rooms/#{channel_id}/peers/#{user_id}/produce", params)
  end

  @impl true
  def consume(channel_id, params) do
    post_json("/rooms/#{channel_id}/consumers", params)
  end

  @impl true
  def resume_consumer(channel_id, consumer_id) do
    post_json("/rooms/#{channel_id}/consumers/#{consumer_id}/resume", %{})
  end

  @impl true
  def producer_action(channel_id, producer_id, action) do
    post_json("/rooms/#{channel_id}/producers/#{producer_id}/#{action}", %{})
  end

  @impl true
  def list_producers(channel_id, exclude_user_id) do
    query = if exclude_user_id, do: "?excludeUserId=#{exclude_user_id}", else: ""
    get_json("/rooms/#{channel_id}/producers#{query}")
  end
end
