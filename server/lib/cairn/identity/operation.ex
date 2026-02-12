defmodule Murmuring.Identity.Operation do
  @moduledoc """
  Ecto schema for DID operation chain entries.

  Each operation in the chain is hash-linked to its predecessor and signed
  by the current rotation key. The chain forms a self-certifying, tamper-evident
  log of identity operations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(create rotate_signing_key rotate_rotation_key update_handle deactivate)

  schema "did_operations" do
    field :did, :string
    field :seq, :integer
    field :operation_type, :string
    field :payload, :map
    field :signature, :binary
    field :prev_hash, :string

    belongs_to :user, Murmuring.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(operation, attrs) do
    operation
    |> cast(attrs, [:did, :seq, :operation_type, :payload, :signature, :prev_hash, :user_id])
    |> validate_required([:did, :seq, :operation_type, :payload, :signature, :user_id])
    |> validate_inclusion(:operation_type, @valid_types)
    |> validate_number(:seq, greater_than_or_equal_to: 0)
    |> unique_constraint([:did, :seq])
  end

  @doc """
  Produces a canonical JSON string from a payload map.

  Keys are sorted alphabetically to ensure deterministic output.
  This is used for hashing and signature verification.
  """
  def canonical_json(payload) when is_map(payload) do
    payload
    |> sort_keys()
    |> Jason.encode!()
  end

  defp sort_keys(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map(fn {k, v} -> {k, sort_keys(v)} end)
    |> Jason.OrderedObject.new()
  end

  defp sort_keys(list) when is_list(list), do: Enum.map(list, &sort_keys/1)
  defp sort_keys(value), do: value
end
