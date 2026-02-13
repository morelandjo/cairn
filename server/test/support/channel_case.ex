defmodule CairnWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import CairnWeb.ChannelCase

      @endpoint CairnWeb.Endpoint
    end
  end

  setup tags do
    Cairn.DataCase.setup_sandbox(tags)
    :ok
  end
end
