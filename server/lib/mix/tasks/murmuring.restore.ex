defmodule Mix.Tasks.Murmuring.Restore do
  @moduledoc """
  Restores a Murmuring backup.

  ## Usage

      mix murmuring.restore /path/to/backup/murmuring-2026-02-11T...

  Restores:
  - PostgreSQL database from dump
  - Upload files from archive
  - Federation keys (if present in backup)
  """

  use Mix.Task

  require Logger

  @shortdoc "Restore Murmuring from backup"

  @impl Mix.Task
  def run([backup_path | _args]) do
    unless File.dir?(backup_path) do
      Mix.shell().error("Backup directory not found: #{backup_path}")
      exit({:shutdown, 1})
    end

    Mix.shell().info("Restoring from: #{backup_path}")

    # Database restore
    dump_path = Path.join(backup_path, "database.pgdump")

    if File.exists?(dump_path) do
      db_config = Application.get_env(:murmuring, Murmuring.Repo, [])

      pg_args = [
        "-h", Keyword.get(db_config, :hostname, "localhost"),
        "-p", to_string(Keyword.get(db_config, :port, 5432)),
        "-U", Keyword.get(db_config, :username, "murmuring"),
        "-d", Keyword.get(db_config, :database, "murmuring"),
        "--clean", "--if-exists",
        dump_path
      ]

      env = [{"PGPASSWORD", Keyword.get(db_config, :password, "")}]

      case System.cmd("pg_restore", pg_args, env: env, stderr_to_stdout: true) do
        {_, 0} ->
          Mix.shell().info("  Database restored")

        {output, _code} ->
          # pg_restore returns non-zero for warnings too
          Mix.shell().info("  Database restored (with warnings): #{String.slice(output, 0, 200)}")
      end
    else
      Mix.shell().info("  No database dump found, skipping")
    end

    # Upload files
    uploads_archive = Path.join(backup_path, "uploads.tar.gz")

    if File.exists?(uploads_archive) do
      upload_root = Application.get_env(:murmuring, Murmuring.Storage.LocalBackend, [])[:root]
      target = if upload_root, do: Path.dirname(upload_root), else: Path.expand("priv")

      case System.cmd("tar", ["xzf", uploads_archive, "-C", target], stderr_to_stdout: true) do
        {_, 0} ->
          Mix.shell().info("  Uploads restored")

        {output, _} ->
          Mix.shell().error("  Upload restore failed: #{output}")
      end
    end

    # Federation keys
    keys_archive = Path.join(backup_path, "keys.tar.gz")

    if File.exists?(keys_archive) do
      case System.cmd("tar", ["xzf", keys_archive, "-C", Path.expand("priv")],
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          Mix.shell().info("  Keys restored")

        {output, _} ->
          Mix.shell().error("  Keys restore failed: #{output}")
      end
    end

    Mix.shell().info("Restore complete")
  end

  def run(_) do
    Mix.shell().error("Usage: mix murmuring.restore /path/to/backup/directory")
  end
end
