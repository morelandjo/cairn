defmodule Cairn.Export do
  @moduledoc """
  The Export context — GDPR data export and account portability.
  """

  import Ecto.Query
  alias Cairn.Repo
  alias Cairn.Accounts
  alias Cairn.Chat

  @export_dir "priv/exports"

  def request_export(user_id) do
    # Enqueue export job
    %{user_id: user_id}
    |> Cairn.Export.DataExportWorker.new()
    |> Oban.insert()
  end

  def generate_export(user_id) do
    user = Accounts.get_user!(user_id)

    export_data = %{
      user: %{
        id: user.id,
        username: user.username,
        display_name: user.display_name,
        is_bot: user.is_bot,
        created_at: user.inserted_at
      },
      messages: export_messages(user_id),
      channels: export_channels(user_id),
      servers: export_servers(user_id),
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Write to JSON file
    File.mkdir_p!(export_path())
    filename = "export_#{user_id}_#{System.system_time(:second)}.json"
    filepath = Path.join(export_path(), filename)

    File.write!(filepath, Jason.encode!(export_data, pretty: true))

    {:ok, %{filename: filename, path: filepath, size: File.stat!(filepath).size}}
  end

  def get_export_file(user_id) do
    export_path()
    |> File.ls!()
    |> Enum.filter(&String.starts_with?(&1, "export_#{user_id}_"))
    |> Enum.sort(:desc)
    |> case do
      [latest | _] -> {:ok, Path.join(export_path(), latest)}
      [] -> {:error, :not_found}
    end
  end

  def export_portability_data(user_id) do
    user = Accounts.get_user!(user_id)

    data = %{
      version: "1.0",
      platform: "cairn",
      user: %{
        username: user.username,
        display_name: user.display_name,
        identity_public_key:
          if(user.identity_public_key, do: Base.encode64(user.identity_public_key), else: nil),
        signed_prekey: if(user.signed_prekey, do: Base.encode64(user.signed_prekey), else: nil),
        signed_prekey_signature:
          if(user.signed_prekey_signature,
            do: Base.encode64(user.signed_prekey_signature),
            else: nil
          )
      },
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, data}
  end

  defp export_messages(user_id) do
    from(m in Chat.Message,
      where: m.author_id == ^user_id and is_nil(m.deleted_at),
      order_by: [asc: m.id],
      limit: 10000,
      select: %{
        id: m.id,
        content: m.content,
        channel_id: m.channel_id,
        inserted_at: m.inserted_at,
        edited_at: m.edited_at
      }
    )
    |> Repo.all()
  end

  defp export_channels(user_id) do
    from(cm in Chat.ChannelMember,
      where: cm.user_id == ^user_id,
      join: c in assoc(cm, :channel),
      select: %{
        id: c.id,
        name: c.name,
        type: c.type,
        server_id: c.server_id
      }
    )
    |> Repo.all()
  end

  defp export_servers(user_id) do
    from(sm in Cairn.Servers.ServerMember,
      where: sm.user_id == ^user_id,
      join: s in assoc(sm, :server),
      select: %{
        id: s.id,
        name: s.name,
        joined_at: sm.inserted_at
      }
    )
    |> Repo.all()
  end

  defp export_path do
    Path.join(Application.app_dir(:cairn), @export_dir)
  end
end
