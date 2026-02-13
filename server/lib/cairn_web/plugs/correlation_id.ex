defmodule CairnWeb.Plugs.CorrelationId do
  @moduledoc """
  Assigns a correlation ID to each request for distributed tracing.
  Uses X-Request-ID if present, otherwise generates a UUID.
  Propagates via Logger metadata.
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    correlation_id =
      case get_req_header(conn, "x-request-id") do
        [id | _] -> id
        [] -> Ecto.UUID.generate()
      end

    Logger.metadata(correlation_id: correlation_id)

    conn
    |> put_resp_header("x-request-id", correlation_id)
    |> assign(:correlation_id, correlation_id)
  end
end
