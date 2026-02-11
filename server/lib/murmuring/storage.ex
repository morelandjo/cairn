defmodule Murmuring.Storage do
  @moduledoc """
  Storage behaviour and dispatcher for file backends.

  Delegates to the configured backend (local filesystem or S3).
  """

  @callback put(key :: String.t(), data :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}
  @callback get(key :: String.t()) :: {:ok, binary()} | {:error, :not_found}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
  @callback exists?(key :: String.t()) :: boolean()

  def put(key, data, content_type), do: backend().put(key, data, content_type)
  def get(key), do: backend().get(key)
  def delete(key), do: backend().delete(key)
  def exists?(key), do: backend().exists?(key)

  defp backend,
    do: Application.get_env(:murmuring, :storage_backend, Murmuring.Storage.LocalBackend)
end
