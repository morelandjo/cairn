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
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Cairn.Repo, fn _repo ->
        case Cairn.Accounts.register_user(%{username: username, password: password}) do
          {:ok, {user, _codes}} ->
            IO.puts("Admin account '#{user.username}' created.")

          {:error, changeset} ->
            IO.puts("Failed to create account:")

            Enum.each(changeset.errors, fn {field, {msg, _}} ->
              IO.puts("  #{field}: #{msg}")
            end)
        end
      end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
