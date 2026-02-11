defmodule MurmuringWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import MurmuringWeb.ChannelCase

      @endpoint MurmuringWeb.Endpoint
    end
  end

  setup tags do
    Murmuring.DataCase.setup_sandbox(tags)
    :ok
  end
end
