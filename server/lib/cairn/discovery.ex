defmodule Murmuring.Discovery do
  @moduledoc """
  The Discovery context — public server directory.
  """

  import Ecto.Query
  alias Murmuring.Repo
  alias Murmuring.Discovery.DirectoryEntry
  alias Murmuring.Servers

  def list_directory(opts \\ []) do
    limit = opts[:limit] || 50
    offset = opts[:offset] || 0
    tag = opts[:tag]

    query =
      from(e in DirectoryEntry,
        join: s in assoc(e, :server),
        order_by: [desc: e.member_count],
        limit: ^limit,
        offset: ^offset,
        select: %{
          id: e.id,
          server_id: e.server_id,
          server_name: s.name,
          description: e.description,
          tags: e.tags,
          member_count: e.member_count,
          listed_at: e.listed_at
        }
      )

    query =
      if tag do
        from(e in query, where: ^tag in e.tags)
      else
        query
      end

    Repo.all(query)
  end

  def list_server(server_id, attrs \\ %{}) do
    member_count = Servers.member_count(server_id)

    case Repo.get_by(DirectoryEntry, server_id: server_id) do
      nil ->
        %DirectoryEntry{}
        |> DirectoryEntry.changeset(
          Map.merge(attrs, %{
            server_id: server_id,
            member_count: member_count,
            listed_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
        )
        |> Repo.insert()

      existing ->
        existing
        |> DirectoryEntry.changeset(Map.merge(attrs, %{member_count: member_count}))
        |> Repo.update()
    end
  end

  def unlist_server(server_id) do
    case Repo.get_by(DirectoryEntry, server_id: server_id) do
      nil -> {:ok, :not_listed}
      entry -> Repo.delete(entry)
    end
  end

  def get_entry(server_id) do
    Repo.get_by(DirectoryEntry, server_id: server_id)
  end

  def update_member_count(server_id) do
    case Repo.get_by(DirectoryEntry, server_id: server_id) do
      nil ->
        :ok

      entry ->
        member_count = Servers.member_count(server_id)
        entry |> DirectoryEntry.changeset(%{member_count: member_count}) |> Repo.update()
    end
  end
end
