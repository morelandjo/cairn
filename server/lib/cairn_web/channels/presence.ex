defmodule CairnWeb.Presence do
  use Phoenix.Presence,
    otp_app: :cairn,
    pubsub_server: Cairn.PubSub
end
