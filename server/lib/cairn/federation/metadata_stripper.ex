defmodule Murmuring.Federation.MetadataStripper do
  @moduledoc """
  Strips sensitive metadata from outbound federation activities.
  Removes IP addresses, user agents, device fingerprints, and internal IDs.
  """

  @sensitive_keys ~w(ip user_agent device_id device_fingerprint session_id
                     internal_id request_id trace_id x_forwarded_for
                     remote_ip client_ip real_ip)

  @doc "Strip sensitive metadata from an outbound activity."
  @spec strip(map()) :: map()
  def strip(activity) when is_map(activity) do
    activity
    |> strip_keys()
    |> strip_nested()
  end

  defp strip_keys(map) when is_map(map) do
    Map.drop(map, @sensitive_keys)
  end

  defp strip_nested(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_map(value) ->
        {key, strip(value)}

      {key, value} when is_list(value) ->
        {key,
         Enum.map(value, fn
           item when is_map(item) -> strip(item)
           item -> item
         end)}

      {key, value} ->
        {key, value}
    end)
  end
end
