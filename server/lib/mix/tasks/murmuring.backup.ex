defmodule Mix.Tasks.Murmuring.Backup do
  @moduledoc """
  Creates a backup of the Murmuring database and uploads.

  ## Usage

      mix murmuring.backup [--output /path/to/backup]

  Creates a timestamped backup containing:
  - PostgreSQL database dump
  - Upload files archive
  - Federation keys (optional, with --include-keys)
  """

  use Mix.Task

  require Logger

  @shortdoc "Back up Murmuring database and files"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          include_keys: :boolean
        ]
      )

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(~r/[:\.]/, "-")
    backup_dir = opts[:output] || Path.expand("priv/backups")
    backup_name = "murmuring-#{timestamp}"
    backup_path = Path.join(backup_dir, backup_name)

    File.mkdir_p!(backup_dir)
    File.mkdir_p!(backup_path)

    Mix.shell().info("Creating backup: #{backup_name}")

    # Database dump
    db_config = Application.get_env(:murmuring, Murmuring.Repo, [])
    dump_path = Path.join(backup_path, "database.pgdump")

    pg_args = [
      "-h", Keyword.get(db_config, :hostname, "localhost"),
      "-p", to_string(Keyword.get(db_config, :port, 5432)),
      "-U", Keyword.get(db_config, :username, "murmuring"),
      "-Fc",
      "-f", dump_path,
      Keyword.get(db_config, :database, "murmuring")
    ]

    env = [{"PGPASSWORD", Keyword.get(db_config, :password, "")}]

    case System.cmd("pg_dump", pg_args, env: env, stderr_to_stdout: true) do
      {_, 0} ->
        Mix.shell().info("  Database dumped: #{dump_path}")

      {output, code} ->
        Mix.shell().error("  pg_dump failed (exit #{code}): #{output}")
    end

    # Upload files
    upload_root = Application.get_env(:murmuring, Murmuring.Storage.LocalBackend, [])[:root]

    if upload_root && File.exists?(upload_root) do
      uploads_archive = Path.join(backup_path, "uploads.tar.gz")

      case System.cmd("tar", ["czf", uploads_archive, "-C", Path.dirname(upload_root), Path.basename(upload_root)],
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          Mix.shell().info("  Uploads archived: #{uploads_archive}")

        {output, _} ->
          Mix.shell().error("  Upload archive failed: #{output}")
      end
    end

    # Federation keys (optional)
    if opts[:include_keys] do
      keys_dir = Path.expand("priv/keys")

      if File.exists?(keys_dir) do
        keys_archive = Path.join(backup_path, "keys.tar.gz")

        case System.cmd("tar", ["czf", keys_archive, "-C", Path.dirname(keys_dir), Path.basename(keys_dir)],
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            Mix.shell().info("  Keys archived: #{keys_archive}")

          {output, _} ->
            Mix.shell().error("  Keys archive failed: #{output}")
        end
      end
    end

    Mix.shell().info("Backup complete: #{backup_path}")
  end
end
