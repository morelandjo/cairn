defmodule Cairn.Chat.SsrfGuardTest do
  use ExUnit.Case, async: true

  alias Cairn.Chat.SsrfGuard

  describe "safe_url?" do
    test "blocks private IPs" do
      refute SsrfGuard.safe_url?("http://127.0.0.1/admin")
      refute SsrfGuard.safe_url?("http://10.0.0.1/secret")
      refute SsrfGuard.safe_url?("http://192.168.1.1/config")
      refute SsrfGuard.safe_url?("http://172.16.0.1/internal")
    end

    test "blocks nil and invalid URLs" do
      refute SsrfGuard.safe_url?(nil)
      refute SsrfGuard.safe_url?("")
      refute SsrfGuard.safe_url?("not a url")
    end

    test "allows public URLs" do
      # This will actually resolve DNS, so use a well-known domain
      assert SsrfGuard.safe_url?("https://example.com")
    end

    test "blocks localhost" do
      refute SsrfGuard.safe_url?("http://localhost/admin")
    end
  end
end
