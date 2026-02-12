defmodule Murmuring.Chat.SsrfGuard do
  @moduledoc """
  SSRF protection: blocks requests to private/internal IP addresses.
  Resolves hostname before allowing fetch.
  """

  def safe_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: nil} -> false
      %URI{host: host} -> safe_host?(host)
    end
  end

  def safe_url?(_), do: false

  defp safe_host?(host) do
    case :inet.getaddr(String.to_charlist(host), :inet) do
      {:ok, ip} -> not private_ip?(ip)
      {:error, _} -> false
    end
  end

  defp private_ip?({a, _, _, _}) when a == 10, do: true
  defp private_ip?({172, b, _, _}) when b >= 16 and b <= 31, do: true
  defp private_ip?({192, 168, _, _}), do: true
  defp private_ip?({127, _, _, _}), do: true
  defp private_ip?({0, _, _, _}), do: true
  defp private_ip?({169, 254, _, _}), do: true
  defp private_ip?(_), do: false
end
