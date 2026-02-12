defmodule MurmuringWeb.UserSocket do
  use Phoenix.Socket

  channel "channel:*", MurmuringWeb.ChannelChannel
  channel "voice:*", MurmuringWeb.VoiceChannel
  channel "user:*", MurmuringWeb.UserChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    # Try local JWT first, then federated token
    case Murmuring.Auth.verify_access_token(token) do
      {:ok, %{"sub" => user_id}} ->
        {:ok, assign(socket, :user_id, user_id) |> assign(:is_federated, false)}

      {:error, _} ->
        try_federated_token(token, socket)
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket) do
    if socket.assigns[:is_federated] do
      "federated_socket:#{socket.assigns.federated_user_id}"
    else
      "user_socket:#{socket.assigns.user_id}"
    end
  end

  defp try_federated_token(token, socket) do
    case Murmuring.Federation.FederatedAuth.verify_token(token) do
      {:ok, claims} ->
        # Look up or create the federated user
        attrs = %{
          did: claims["did"],
          username: claims["username"],
          display_name: claims["display_name"],
          home_instance: claims["home_instance"],
          public_key: Base.decode64!(claims["public_key"]),
          actor_uri: "https://#{claims["home_instance"]}/users/#{claims["username"]}",
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        }

        case Murmuring.Federation.get_or_create_federated_user(attrs) do
          {:ok, federated_user} ->
            socket =
              socket
              |> assign(:is_federated, true)
              |> assign(:federated_user_id, federated_user.id)
              |> assign(:federated_user, federated_user)
              |> assign(:user_id, federated_user.id)

            {:ok, socket}

          _ ->
            :error
        end

      {:error, _} ->
        :error
    end
  end
end
