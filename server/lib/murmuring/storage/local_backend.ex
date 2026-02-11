defmodule Murmuring.Storage.LocalBackend do
  @moduledoc """
  Content-addressable local filesystem storage backend.

  Files are stored under a sharded directory structure using the first
  two characters of the storage key: `<root>/ab/abcdef1234...`
  """

  @behaviour Murmuring.Storage

  @impl true
  def put(key, data, _content_type) do
    path = file_path(key)
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(key) do
    path = file_path(key)

    case File.read(path) do
      {:ok, data} -> {:ok, data}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    path = file_path(key)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(key) do
    key |> file_path() |> File.exists?()
  end

  defp file_path(key) do
    root = root_dir()
    shard = String.slice(key, 0, 2)
    Path.join([root, shard, key])
  end

  defp root_dir do
    config = Application.get_env(:murmuring, Murmuring.Storage.LocalBackend, [])
    Keyword.get(config, :root, Path.expand("priv/uploads"))
  end
end
