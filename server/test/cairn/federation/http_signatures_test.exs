defmodule Murmuring.Federation.HttpSignaturesTest do
  use ExUnit.Case, async: true

  alias Murmuring.Federation.HttpSignatures
  alias Murmuring.Federation.ContentDigest

  setup do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    sign_fn = fn message -> :crypto.sign(:eddsa, :none, message, [private_key, :ed25519]) end
    %{public_key: public_key, private_key: private_key, sign_fn: sign_fn}
  end

  describe "ContentDigest" do
    test "compute and verify roundtrip" do
      body = ~s({"type": "Create", "object": "hello"})
      digest = ContentDigest.compute(body)
      assert String.starts_with?(digest, "sha-256=:")
      assert ContentDigest.verify(digest, body)
    end

    test "verify rejects tampered body" do
      body = "original body"
      digest = ContentDigest.compute(body)
      refute ContentDigest.verify(digest, "tampered body")
    end

    test "verify rejects invalid header" do
      refute ContentDigest.verify("invalid-header", "body")
    end
  end

  describe "sign_request/5" do
    test "returns required headers for POST with body", %{sign_fn: sign_fn} do
      headers =
        HttpSignatures.sign_request(
          "POST",
          "https://remote.example.com/inbox",
          %{"content-type" => "application/activity+json"},
          ~s({"type": "Create"}),
          sign_fn
        )

      assert headers["signature-input"]
      assert headers["signature"]
      assert headers["content-digest"]
      assert headers["date"]

      # Verify signature-input format
      assert headers["signature-input"] =~ ~r/sig1=\(/
      assert headers["signature-input"] =~ "\"@method\""
      assert headers["signature-input"] =~ "\"content-digest\""
      assert headers["signature-input"] =~ "created="
    end

    test "omits content-digest for bodyless requests", %{sign_fn: sign_fn} do
      headers =
        HttpSignatures.sign_request(
          "GET",
          "https://remote.example.com/users/alice",
          %{},
          nil,
          sign_fn
        )

      assert headers["signature-input"]
      assert headers["signature"]
      refute headers["content-digest"]
      assert headers["date"]
    end
  end

  describe "verify_request/2" do
    test "verifies a valid signed request", %{public_key: public_key, sign_fn: sign_fn} do
      body = ~s({"type": "Create"})

      headers =
        HttpSignatures.sign_request(
          "POST",
          "https://local.example.com/inbox",
          %{"content-type" => "application/activity+json"},
          body,
          sign_fn
        )

      request = %{
        method: "POST",
        url: "https://local.example.com/inbox",
        headers: headers,
        body: body
      }

      assert :ok = HttpSignatures.verify_request(request, public_key)
    end

    test "rejects tampered body", %{public_key: public_key, sign_fn: sign_fn} do
      body = ~s({"type": "Create"})

      headers =
        HttpSignatures.sign_request(
          "POST",
          "https://local.example.com/inbox",
          %{"content-type" => "application/activity+json"},
          body,
          sign_fn
        )

      request = %{
        method: "POST",
        url: "https://local.example.com/inbox",
        headers: headers,
        body: ~s({"type": "Delete"})
      }

      assert {:error, :content_digest_mismatch} =
               HttpSignatures.verify_request(request, public_key)
    end

    test "rejects wrong public key", %{sign_fn: sign_fn} do
      {other_pub, _other_priv} = :crypto.generate_key(:eddsa, :ed25519)
      body = ~s({"type": "Create"})

      headers =
        HttpSignatures.sign_request(
          "POST",
          "https://local.example.com/inbox",
          %{"content-type" => "application/activity+json"},
          body,
          sign_fn
        )

      request = %{
        method: "POST",
        url: "https://local.example.com/inbox",
        headers: headers,
        body: body
      }

      assert {:error, :invalid_signature} = HttpSignatures.verify_request(request, other_pub)
    end

    test "rejects expired date header", %{public_key: public_key, sign_fn: sign_fn} do
      body = ~s({"type": "Create"})

      headers =
        HttpSignatures.sign_request(
          "POST",
          "https://local.example.com/inbox",
          %{"content-type" => "application/activity+json"},
          body,
          sign_fn
        )

      # Tamper with the date to be old (but don't tamper with the signature base —
      # the signature will still be for the original date, so we need to rebuild)
      old_date = DateTime.utc_now() |> DateTime.add(-600, :second)
      old_date_str = Calendar.strftime(old_date, "%a, %d %b %Y %H:%M:%S GMT")

      old_headers = Map.put(headers, "date", old_date_str)

      request = %{
        method: "POST",
        url: "https://local.example.com/inbox",
        headers: old_headers,
        body: body
      }

      # This should fail because date is too old
      assert {:error, :date_expired} = HttpSignatures.verify_request(request, public_key)
    end

    test "rejects missing signature", %{public_key: public_key} do
      request = %{
        method: "POST",
        url: "https://local.example.com/inbox",
        headers: %{"date" => "Mon, 10 Feb 2026 15:00:00 GMT"},
        body: ""
      }

      assert {:error, :missing_signature_input} =
               HttpSignatures.verify_request(request, public_key)
    end

    test "verifies bodyless GET request", %{public_key: public_key, sign_fn: sign_fn} do
      headers =
        HttpSignatures.sign_request(
          "GET",
          "https://local.example.com/users/alice",
          %{},
          nil,
          sign_fn
        )

      request = %{
        method: "GET",
        url: "https://local.example.com/users/alice",
        headers: headers,
        body: nil
      }

      assert :ok = HttpSignatures.verify_request(request, public_key)
    end
  end
end
