defmodule MurmuringWeb.InboxController do
  use MurmuringWeb, :controller

  alias Murmuring.Federation.InboxHandler

  @doc "POST /inbox — receives ActivityPub activities from federated nodes."
  def create(conn, params) do
    # The VerifyHttpSignature plug sets :federation_node
    node = conn.assigns[:federation_node]

    case InboxHandler.handle(params, node) do
      :ok ->
        conn
        |> put_status(202)
        |> json(%{status: "accepted"})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: reason})
    end
  end
end
