defmodule Murmuring.Federation.ContentDigest do
  @moduledoc """
  Implements Content-Digest header per RFC 9530.
  Uses SHA-256 for body integrity verification.
  """

  @doc "Computes the Content-Digest header value for a body."
  @spec compute(binary()) :: String.t()
  def compute(body) when is_binary(body) do
    hash = :crypto.hash(:sha256, body)
    "sha-256=:#{Base.encode64(hash)}:"
  end

  @doc "Verifies a Content-Digest header against a body."
  @spec verify(String.t(), binary()) :: boolean()
  def verify(header, body) when is_binary(header) and is_binary(body) do
    case parse(header) do
      {:ok, :sha256, expected_hash} ->
        actual_hash = :crypto.hash(:sha256, body)
        actual_hash == expected_hash

      _ ->
        false
    end
  end

  defp parse(header) do
    case Regex.run(~r/sha-256=:([A-Za-z0-9+\/=]+):/, header) do
      [_, b64] ->
        case Base.decode64(b64) do
          {:ok, hash} -> {:ok, :sha256, hash}
          :error -> {:error, :invalid_base64}
        end

      _ ->
        {:error, :unsupported_algorithm}
    end
  end
end
