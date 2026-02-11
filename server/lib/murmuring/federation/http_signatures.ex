defmodule Murmuring.Federation.HttpSignatures do
  @moduledoc """
  HTTP Message Signatures per RFC 9421.

  Signs outbound requests and verifies inbound requests using Ed25519.
  Covered components: @method, @target-uri, @authority, content-type,
  content-digest, date.
  """

  alias Murmuring.Federation.ContentDigest

  # seconds
  @max_clock_skew 300

  @doc """
  Signs an outbound HTTP request.

  Returns a map of headers to add to the request:
  - `signature-input` — describes the covered components
  - `signature` — the actual Ed25519 signature
  - `content-digest` — SHA-256 digest of the body (if body present)
  - `date` — RFC 7231 date header

  ## Parameters
  - `method` — HTTP method string (e.g., "POST")
  - `url` — full target URL (e.g., "https://remote.example.com/inbox")
  - `headers` — existing request headers as a map
  - `body` — request body (binary), or nil for bodyless requests
  - `sign_fn` — function that takes a binary and returns a signature binary
  """
  @spec sign_request(String.t(), String.t(), map(), binary() | nil, (binary() -> binary())) ::
          map()
  def sign_request(method, url, headers, body, sign_fn) do
    uri = URI.parse(url)
    date = format_http_date(DateTime.utc_now())

    # Build headers map with date
    headers = Map.put(headers, "date", date)

    # Add content-digest for requests with body
    headers =
      if body && byte_size(body) > 0 do
        Map.put(headers, "content-digest", ContentDigest.compute(body))
      else
        headers
      end

    # Determine covered components
    components =
      if body && byte_size(body) > 0 do
        ["@method", "@target-uri", "@authority", "content-type", "content-digest", "date"]
      else
        ["@method", "@target-uri", "@authority", "date"]
      end

    # Build signature base
    signature_base = build_signature_base(components, method, url, uri, headers)

    # Sign
    signature = sign_fn.(signature_base)

    # Build Signature-Input header
    component_list = components |> Enum.map(&"\"#{&1}\"") |> Enum.join(" ")
    created = DateTime.utc_now() |> DateTime.to_unix()
    sig_input = "sig1=(#{component_list});created=#{created};keyid=\"node-key\""

    # Build Signature header
    sig_value = "sig1=:#{Base.encode64(signature)}:"

    headers
    |> Map.put("signature-input", sig_input)
    |> Map.put("signature", sig_value)
  end

  @doc """
  Verifies an inbound HTTP request's signature.

  ## Parameters
  - `conn_or_map` — a map with keys: method, url, headers, body
  - `public_key` — the Ed25519 public key to verify against

  Returns `:ok` or `{:error, reason}`.
  """
  @spec verify_request(map(), binary()) :: :ok | {:error, atom()}
  def verify_request(%{method: method, url: url, headers: headers, body: body}, public_key) do
    with {:ok, _sig_id, components, params} <- parse_signature_input(headers),
         {:ok, signature} <- parse_signature(headers),
         :ok <- check_date(headers),
         :ok <- check_content_digest(headers, body),
         :ok <- check_created(params) do
      uri = URI.parse(url)
      signature_base = build_signature_base(components, method, url, uri, headers)

      if :crypto.verify(:eddsa, :none, signature_base, signature, [public_key, :ed25519]) do
        :ok
      else
        {:error, :invalid_signature}
      end
    end
  end

  # ── Private: Signature Base Construction ──

  defp build_signature_base(components, method, url, uri, headers) do
    lines =
      Enum.map(components, fn
        "@method" -> "\"@method\": #{String.upcase(method)}"
        "@target-uri" -> "\"@target-uri\": #{url}"
        "@authority" -> "\"@authority\": #{authority(uri)}"
        header -> "\"#{header}\": #{Map.get(headers, header, "")}"
      end)

    Enum.join(lines, "\n")
  end

  defp authority(%URI{host: host, port: port, scheme: scheme}) do
    default_port = if scheme == "https", do: 443, else: 80

    if port && port != default_port do
      "#{host}:#{port}"
    else
      host
    end
  end

  # ── Private: Parsing ──

  defp parse_signature_input(headers) do
    case Map.get(headers, "signature-input") do
      nil ->
        {:error, :missing_signature_input}

      input ->
        # Parse: sig1=("@method" "@target-uri" ...);created=123;keyid="node-key"
        case Regex.run(~r/(\w+)=\(([^)]*)\)(.*)/, input) do
          [_, sig_id, components_str, params_str] ->
            components =
              Regex.scan(~r/"([^"]+)"/, components_str)
              |> Enum.map(fn [_, c] -> c end)

            params = parse_params(params_str)
            {:ok, sig_id, components, params}

          _ ->
            {:error, :invalid_signature_input}
        end
    end
  end

  defp parse_params(str) do
    Regex.scan(~r/;(\w+)=(?:"([^"]*)"|(\d+))/, str)
    |> Enum.reduce(%{}, fn
      [_, key, value, ""], acc -> Map.put(acc, key, value)
      [_, key, "", value], acc -> Map.put(acc, key, String.to_integer(value))
      [_, key, value], acc -> Map.put(acc, key, value)
    end)
  end

  defp parse_signature(headers) do
    case Map.get(headers, "signature") do
      nil ->
        {:error, :missing_signature}

      sig_header ->
        case Regex.run(~r/\w+=:([A-Za-z0-9+\/=]+):/, sig_header) do
          [_, b64] ->
            case Base.decode64(b64) do
              {:ok, sig} -> {:ok, sig}
              :error -> {:error, :invalid_signature_encoding}
            end

          _ ->
            {:error, :invalid_signature_format}
        end
    end
  end

  # ── Private: Validation ──

  defp check_date(headers) do
    case Map.get(headers, "date") do
      nil ->
        {:error, :missing_date}

      date_str ->
        case parse_http_date(date_str) do
          {:ok, date} ->
            diff = abs(DateTime.diff(DateTime.utc_now(), date, :second))

            if diff <= @max_clock_skew do
              :ok
            else
              {:error, :date_expired}
            end

          _ ->
            {:error, :invalid_date}
        end
    end
  end

  defp check_content_digest(headers, body) do
    case Map.get(headers, "content-digest") do
      nil ->
        # No digest header — OK if no body
        :ok

      digest ->
        if ContentDigest.verify(digest, body || "") do
          :ok
        else
          {:error, :content_digest_mismatch}
        end
    end
  end

  defp check_created(params) do
    case Map.get(params, "created") do
      nil ->
        :ok

      created when is_integer(created) ->
        now = DateTime.utc_now() |> DateTime.to_unix()
        diff = abs(now - created)

        if diff <= @max_clock_skew do
          :ok
        else
          {:error, :signature_expired}
        end
    end
  end

  # ── Private: Date Formatting ──

  @days ~w(Mon Tue Wed Thu Fri Sat Sun)
  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  defp format_http_date(%DateTime{} = dt) do
    day_name = Enum.at(@days, Date.day_of_week(dt) - 1)
    month_name = Enum.at(@months, dt.month - 1)

    "#{day_name}, #{String.pad_leading("#{dt.day}", 2, "0")} #{month_name} #{dt.year} " <>
      "#{String.pad_leading("#{dt.hour}", 2, "0")}:#{String.pad_leading("#{dt.minute}", 2, "0")}:#{String.pad_leading("#{dt.second}", 2, "0")} GMT"
  end

  defp parse_http_date(str) do
    # Parse RFC 7231 date: "Mon, 10 Feb 2026 15:30:00 GMT"
    case Regex.run(
           ~r/\w+, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT/,
           str
         ) do
      [_, day, month_str, year, hour, min, sec] ->
        month_idx = Enum.find_index(@months, &(&1 == month_str))

        if month_idx do
          case DateTime.new(
                 Date.new!(
                   String.to_integer(year),
                   month_idx + 1,
                   String.to_integer(day)
                 ),
                 Time.new!(
                   String.to_integer(hour),
                   String.to_integer(min),
                   String.to_integer(sec)
                 ),
                 "Etc/UTC"
               ) do
            {:ok, dt} -> {:ok, dt}
            _ -> {:error, :invalid_date}
          end
        else
          {:error, :invalid_month}
        end

      _ ->
        {:error, :invalid_format}
    end
  end
end
