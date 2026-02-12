defmodule MurmuringWeb.VoiceController do
  use MurmuringWeb, :controller

  # 12 hours
  @turn_ttl 12 * 60 * 60

  def turn_credentials(conn, _params) do
    user_id = conn.assigns.current_user.id
    turn_secret = Application.get_env(:murmuring, :turn_secret, "dev-turn-secret")
    turn_urls = Application.get_env(:murmuring, :turn_urls, [])

    if turn_urls == [] do
      json(conn, %{iceServers: []})
    else
      timestamp = System.system_time(:second) + @turn_ttl
      username = "#{timestamp}:#{user_id}"
      credential = :crypto.mac(:hmac, :sha, turn_secret, username) |> Base.encode64()

      json(conn, %{
        iceServers: [
          %{
            urls: turn_urls,
            username: username,
            credential: credential
          }
        ]
      })
    end
  end

  def ice_servers(conn, _params) do
    turn_urls = Application.get_env(:murmuring, :turn_urls, [])

    stun_servers = [
      %{urls: ["stun:stun.l.google.com:19302"]}
    ]

    turn_servers =
      if turn_urls != [] do
        user_id = conn.assigns.current_user.id
        turn_secret = Application.get_env(:murmuring, :turn_secret, "dev-turn-secret")
        timestamp = System.system_time(:second) + @turn_ttl
        username = "#{timestamp}:#{user_id}"
        credential = :crypto.mac(:hmac, :sha, turn_secret, username) |> Base.encode64()

        [
          %{
            urls: turn_urls,
            username: username,
            credential: credential
          }
        ]
      else
        []
      end

    json(conn, %{iceServers: stun_servers ++ turn_servers})
  end
end
