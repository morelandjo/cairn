defmodule Cairn.Repo do
  use Ecto.Repo,
    otp_app: :cairn,
    adapter: Ecto.Adapters.Postgres
end
