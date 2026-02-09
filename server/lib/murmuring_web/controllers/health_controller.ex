defmodule MurmuringWeb.HealthController do
  use MurmuringWeb, :controller

  def index(conn, _params) do
    postgres_status = check_postgres()
    redis_status = check_redis()

    all_healthy = postgres_status == :up and redis_status == :up
    status_code = if all_healthy, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(%{
      status: if(all_healthy, do: "healthy", else: "degraded"),
      version: "0.1.0",
      postgres: Atom.to_string(postgres_status),
      redis: Atom.to_string(redis_status)
    })
  end

  defp check_postgres do
    case Ecto.Adapters.SQL.query(Murmuring.Repo, "SELECT 1") do
      {:ok, _} -> :up
      {:error, _} -> :down
    end
  rescue
    _ -> :down
  end

  defp check_redis do
    case Redix.command(:murmuring_redis, ["PING"]) do
      {:ok, "PONG"} -> :up
      _ -> :down
    end
  rescue
    _ -> :down
  end
end
