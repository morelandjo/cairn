defmodule Cairn.Release do
  @moduledoc """
  Release tasks for running outside of Mix (in production releases).
  Used via: bin/cairn eval "Cairn.Release.migrate()"
  """

  @app :cairn

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create_admin(username, password) do
    start_app()

    case Cairn.Accounts.register_user(%{username: username, password: password}) do
      {:ok, {user, _codes}} ->
        IO.puts("Admin account '#{user.username}' created.")

      {:error, changeset} ->
        IO.puts("Failed to create account:")

        Enum.each(changeset.errors, fn {field, {msg, _}} ->
          IO.puts("  #{field}: #{msg}")
        end)
    end
  end

  def list_nodes do
    start_app()

    nodes = Cairn.Federation.list_nodes()

    if Enum.empty?(nodes) do
      IO.puts("No federated nodes.")
    else
      Enum.each(nodes, fn n ->
        secure = if n.secure, do: "secure", else: "insecure"
        IO.puts("#{n.domain} [#{n.status}] #{secure}")
      end)
    end
  end

  defp start_app do
    # Disable the web server — eval runs inside the container where port 4000 is already bound.
    # runtime.exs is already evaluated at boot, so we override the endpoint config directly.
    endpoint_config = Application.get_env(:cairn, CairnWeb.Endpoint, [])
    Application.put_env(:cairn, CairnWeb.Endpoint, Keyword.put(endpoint_config, :server, false))
    Application.put_env(:cairn, :start_prom_ex, false)
    Application.ensure_all_started(@app)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
