defmodule Murmuring.Chat.Sanitizer do
  @moduledoc """
  Sanitizes message content: strips HTML, blocks dangerous URIs,
  enforces length limits, and strips bidi overrides.
  """

  @max_length 4000

  @bidi_chars [
    "\u200E",
    "\u200F",
    "\u202A",
    "\u202B",
    "\u202C",
    "\u202D",
    "\u202E",
    "\u2066",
    "\u2067",
    "\u2068",
    "\u2069"
  ]

  @dangerous_uri_schemes ~w(javascript vbscript data)

  def sanitize(content) when is_binary(content) do
    content
    |> strip_html()
    |> strip_bidi()
    |> strip_dangerous_uris()
    |> enforce_length()
  end

  def sanitize(nil), do: nil

  defp strip_html(content) do
    Regex.replace(~r/<[^>]*>/, content, "")
  end

  defp strip_bidi(content) do
    Enum.reduce(@bidi_chars, content, fn char, acc ->
      String.replace(acc, char, "")
    end)
  end

  defp strip_dangerous_uris(content) do
    Enum.reduce(@dangerous_uri_schemes, content, fn scheme, acc ->
      Regex.replace(~r/#{scheme}\s*:/i, acc, "#{scheme}_blocked:")
    end)
  end

  defp enforce_length(content) do
    if String.length(content) > @max_length do
      String.slice(content, 0, @max_length)
    else
      content
    end
  end
end
