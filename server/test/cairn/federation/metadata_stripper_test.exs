defmodule Murmuring.Federation.MetadataStripperTest do
  use ExUnit.Case, async: true

  alias Murmuring.Federation.MetadataStripper

  test "strips sensitive top-level keys" do
    activity = %{
      "type" => "Create",
      "actor" => "https://example.com/users/alice",
      "ip" => "192.168.1.1",
      "user_agent" => "Mozilla/5.0",
      "device_id" => "abc123",
      "session_id" => "sess_xyz",
      "request_id" => "req_123"
    }

    result = MetadataStripper.strip(activity)

    assert result["type"] == "Create"
    assert result["actor"] == "https://example.com/users/alice"
    refute Map.has_key?(result, "ip")
    refute Map.has_key?(result, "user_agent")
    refute Map.has_key?(result, "device_id")
    refute Map.has_key?(result, "session_id")
    refute Map.has_key?(result, "request_id")
  end

  test "strips sensitive keys from nested objects" do
    activity = %{
      "type" => "Create",
      "object" => %{
        "type" => "Note",
        "content" => "Hello",
        "ip" => "10.0.0.1",
        "device_fingerprint" => "fp_123"
      }
    }

    result = MetadataStripper.strip(activity)

    assert result["object"]["type"] == "Note"
    assert result["object"]["content"] == "Hello"
    refute Map.has_key?(result["object"], "ip")
    refute Map.has_key?(result["object"], "device_fingerprint")
  end

  test "strips sensitive keys from items in lists" do
    activity = %{
      "type" => "Collection",
      "items" => [
        %{"type" => "Note", "ip" => "1.2.3.4", "content" => "A"},
        %{"type" => "Note", "user_agent" => "bot", "content" => "B"}
      ]
    }

    result = MetadataStripper.strip(activity)

    assert length(result["items"]) == 2
    refute Map.has_key?(Enum.at(result["items"], 0), "ip")
    refute Map.has_key?(Enum.at(result["items"], 1), "user_agent")
    assert Enum.at(result["items"], 0)["content"] == "A"
  end

  test "preserves non-sensitive keys" do
    activity = %{
      "type" => "Create",
      "actor" => "https://example.com/users/alice",
      "object" => %{"type" => "Note", "content" => "Hello"},
      "published" => "2026-02-10T15:00:00Z"
    }

    result = MetadataStripper.strip(activity)
    assert result == activity
  end
end
