defmodule MurmuringWeb.Presence do
  use Phoenix.Presence,
    otp_app: :murmuring,
    pubsub_server: Murmuring.PubSub
end
