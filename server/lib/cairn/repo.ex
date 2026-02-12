defmodule Murmuring.Repo do
  use Ecto.Repo,
    otp_app: :murmuring,
    adapter: Ecto.Adapters.Postgres
end
