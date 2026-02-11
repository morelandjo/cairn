defmodule Murmuring.Storage.S3Backend do
  @moduledoc """
  S3-compatible storage backend using ExAws.

  Stores files in a configurable S3 bucket, using the same key naming
  scheme as the local backend (sharded by first 2 chars of hash).
  """

  @behaviour Murmuring.Storage

  @impl true
  def put(key, data, content_type) do
    bucket = bucket()

    case ExAws.S3.put_object(bucket, object_key(key), data, content_type: content_type)
         |> ExAws.request(ex_aws_config()) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(key) do
    bucket = bucket()

    case ExAws.S3.get_object(bucket, object_key(key))
         |> ExAws.request(ex_aws_config()) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    bucket = bucket()

    case ExAws.S3.delete_object(bucket, object_key(key))
         |> ExAws.request(ex_aws_config()) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(key) do
    bucket = bucket()

    case ExAws.S3.head_object(bucket, object_key(key))
         |> ExAws.request(ex_aws_config()) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp object_key(key) do
    shard = String.slice(key, 0, 2)
    "#{shard}/#{key}"
  end

  defp bucket do
    config = Application.get_env(:murmuring, Murmuring.Storage.S3Backend, [])
    Keyword.fetch!(config, :bucket)
  end

  defp ex_aws_config do
    config = Application.get_env(:murmuring, Murmuring.Storage.S3Backend, [])

    base = [region: Keyword.get(config, :region, "us-east-1")]

    case Keyword.get(config, :endpoint) do
      nil -> base
      endpoint -> Keyword.put(base, :host, endpoint)
    end
  end
end
