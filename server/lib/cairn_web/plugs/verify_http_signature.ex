defmodule CairnWeb.Plugs.VerifyHttpSignature do
  @moduledoc """
  Plug for verifying HTTP message signatures on federation inbox routes.
  Returns 401 on verification failure.
  """

  import Plug.Conn
  alias Cairn.Federation
  alias Cairn.Federation.HttpSignatures

  def init(opts), do: opts

  def call(conn, _opts) do
    # Read the cached body (requires Plug.Parsers with :read_body or custom body reader)
    body = conn.assigns[:raw_body] || ""

    # Extract the signing node's domain from the @authority or signature keyid
    headers = extract_headers(conn)

    # Determine the remote node's domain from the request
    case determine_remote_domain(headers) do
      {:ok, domain} ->
        case Federation.get_node_by_domain(domain) do
          nil ->
            reject(conn, "Unknown federation node")

          %{status: "blocked"} ->
            reject(conn, "Node is blocked")

          node ->
            request = %{
              method: conn.method,
              url: build_request_url(conn),
              headers: headers,
              body: body
            }

            public_key = Base.decode64!(node.public_key)

            case HttpSignatures.verify_request(request, public_key) do
              :ok ->
                assign(conn, :federation_node, node)

              {:error, reason} ->
                reject(conn, "Signature verification failed: #{reason}")
            end
        end

      {:error, _reason} ->
        reject(conn, "Could not determine remote node")
    end
  end

  defp extract_headers(conn) do
    conn.req_headers
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, String.downcase(key), value)
    end)
  end

  defp build_request_url(conn) do
    "#{conn.scheme}://#{conn.host}#{conn.request_path}"
  end

  defp determine_remote_domain(headers) do
    # Try to extract domain from signature-input keyid or authority
    case Map.get(headers, "signature-input") do
      nil ->
        {:error, :no_signature}

      input ->
        # Try keyid first: ;keyid="node-key@domain.com"
        case Regex.run(~r/keyid="[^@]*@([^"]+)"/, input) do
          [_, domain] ->
            {:ok, domain}

          _ ->
            # Fall back to the authority header
            case Map.get(headers, "host") do
              nil -> {:error, :no_host}
              host -> {:ok, host |> String.split(":") |> hd()}
            end
        end
    end
  end

  defp reject(conn, message) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: message})
    |> halt()
  end
end
