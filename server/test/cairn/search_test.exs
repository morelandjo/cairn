defmodule Cairn.SearchTest do
  use Cairn.DataCase, async: true

  alias Cairn.Search

  describe "search module" do
    test "ensure_index doesn't crash when Meilisearch is unavailable" do
      # This tests that the module doesn't hard-fail when Meilisearch isn't up
      # In CI/dev without Meilisearch, this should return an error tuple
      result = Search.ensure_index()
      # We just check it doesn't raise
      assert is_tuple(result)
    end

    test "search returns error when Meilisearch is unavailable" do
      result = Search.search("test query")
      assert {:error, _} = result
    end
  end
end
