defmodule Cairn.Federation.HLCTest do
  use ExUnit.Case, async: true

  alias Cairn.Federation.HLC

  setup do
    {:ok, pid} =
      HLC.start_link(name: :"hlc_#{:erlang.unique_integer([:positive])}", node_id: "test-node")

    %{hlc: pid}
  end

  describe "now/1" do
    test "returns monotonically increasing timestamps", %{hlc: hlc} do
      {w1, c1, n1} = HLC.now(hlc)
      {w2, c2, n2} = HLC.now(hlc)

      assert n1 == "test-node"
      assert n2 == "test-node"

      # Second timestamp must be >= first
      assert HLC.compare({w2, c2, n2}, {w1, c1, n1}) in [:gt, :eq]
    end

    test "increments counter when wall time is same", %{hlc: hlc} do
      # Call quickly enough that wall time may be the same
      {w1, _c1, _n1} = HLC.now(hlc)
      {w2, c2, _n2} = HLC.now(hlc)

      if w1 == w2 do
        assert c2 > 0
      end
    end
  end

  describe "update/4" do
    test "advances past remote timestamp", %{hlc: hlc} do
      # Set remote time far in the future (but within drift limit)
      future_wall = System.os_time(:millisecond) + 5_000

      {:ok, {w, _c, _n}} = HLC.update(future_wall, 10, "remote-node", hlc)

      # Local clock should have advanced past remote
      assert w >= future_wall
    end

    test "rejects excessive clock drift", %{hlc: hlc} do
      # Set remote time way too far in the future (> 60s)
      far_future = System.os_time(:millisecond) + 120_000

      assert {:error, :clock_drift} = HLC.update(far_future, 0, "remote-node", hlc)
    end

    test "maintains monotonicity after update", %{hlc: hlc} do
      {w1, c1, n1} = HLC.now(hlc)

      # Update with a slightly future remote time
      remote_wall = System.os_time(:millisecond) + 1_000
      {:ok, {w2, c2, n2}} = HLC.update(remote_wall, 5, "remote-node", hlc)

      {w3, c3, n3} = HLC.now(hlc)

      # Each successive timestamp must be >= previous
      assert HLC.compare({w2, c2, n2}, {w1, c1, n1}) in [:gt, :eq]
      assert HLC.compare({w3, c3, n3}, {w2, c2, n2}) in [:gt, :eq]
    end
  end

  describe "compare/2" do
    test "compares by wall time first" do
      assert HLC.compare({100, 0, "a"}, {200, 0, "a"}) == :lt
      assert HLC.compare({200, 0, "a"}, {100, 0, "a"}) == :gt
    end

    test "compares by counter when wall times equal" do
      assert HLC.compare({100, 1, "a"}, {100, 2, "a"}) == :lt
      assert HLC.compare({100, 2, "a"}, {100, 1, "a"}) == :gt
    end

    test "compares by node id as tiebreaker" do
      assert HLC.compare({100, 1, "a"}, {100, 1, "b"}) == :lt
      assert HLC.compare({100, 1, "b"}, {100, 1, "a"}) == :gt
    end

    test "equal timestamps" do
      assert HLC.compare({100, 1, "a"}, {100, 1, "a"}) == :eq
    end
  end
end
