defmodule Cairn.Types.UUIDv7 do
  @moduledoc """
  An Ecto type for UUIDv7 identifiers.

  UUIDv7 encodes a Unix timestamp in the high bits, providing
  natural time-ordering for database indexes and cursor pagination.
  """

  use Ecto.Type

  @impl true
  def type, do: :uuid

  @impl true
  def cast(<<_::288>> = hex_string) do
    case Ecto.UUID.cast(hex_string) do
      {:ok, _} = ok -> ok
      :error -> :error
    end
  end

  def cast(<<_::128>> = raw), do: {:ok, Ecto.UUID.load!(raw)}
  def cast(_), do: :error

  @impl true
  def load(<<_::128>> = raw), do: {:ok, Ecto.UUID.load!(raw)}
  def load(_), do: :error

  @impl true
  def dump(<<_::288>> = hex_string) do
    Ecto.UUID.dump(hex_string)
  end

  def dump(_), do: :error

  @doc """
  Generates a new UUIDv7 string.
  """
  def generate do
    Uniq.UUID.uuid7()
  end

  @impl true
  def autogenerate do
    generate()
  end
end
