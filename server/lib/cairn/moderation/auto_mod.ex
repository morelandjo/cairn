defmodule Cairn.Moderation.AutoMod do
  @moduledoc """
  Auto-moderation engine. Runs synchronously before message creation.
  Checks content against server-specific rules.
  Returns :ok or {:violation, action, rule_type}.
  """

  import Ecto.Query
  alias Cairn.Repo
  alias Cairn.Moderation.AutoModRule

  def check_message(server_id, content) when is_binary(content) do
    rules = get_enabled_rules(server_id)
    check_rules(rules, content)
  end

  def check_message(_server_id, _content), do: :ok

  defp get_enabled_rules(server_id) do
    from(r in AutoModRule,
      where: r.server_id == ^server_id and r.enabled == true
    )
    |> Repo.all()
  end

  defp check_rules([], _content), do: :ok

  defp check_rules([rule | rest], content) do
    case check_rule(rule, content) do
      :ok -> check_rules(rest, content)
      violation -> violation
    end
  end

  defp check_rule(%{rule_type: "word_filter", config: config}, content) do
    words = Map.get(config, "words", [])
    action = Map.get(config, "action", "delete")
    content_lower = String.downcase(content)

    if Enum.any?(words, fn word -> String.contains?(content_lower, String.downcase(word)) end) do
      {:violation, action, "word_filter"}
    else
      :ok
    end
  end

  defp check_rule(%{rule_type: "regex_filter", config: config}, content) do
    patterns = Map.get(config, "patterns", [])
    action = Map.get(config, "action", "delete")

    if Enum.any?(patterns, fn pattern ->
         case Regex.compile(pattern) do
           {:ok, regex} -> Regex.match?(regex, content)
           _ -> false
         end
       end) do
      {:violation, action, "regex_filter"}
    else
      :ok
    end
  end

  defp check_rule(%{rule_type: "link_filter", config: config}, content) do
    action = Map.get(config, "action", "delete")

    if Regex.match?(~r/https?:\/\/\S+/, content) do
      allowed = Map.get(config, "allowed_domains", [])

      if allowed == [] do
        {:violation, action, "link_filter"}
      else
        urls = Regex.scan(~r/https?:\/\/([^\s\/]+)/, content, capture: :all_but_first)
        domains = Enum.map(urls, fn [domain] -> domain end)

        if Enum.all?(domains, fn domain ->
             Enum.any?(allowed, fn allowed_domain ->
               String.ends_with?(domain, allowed_domain)
             end)
           end) do
          :ok
        else
          {:violation, action, "link_filter"}
        end
      end
    else
      :ok
    end
  end

  defp check_rule(%{rule_type: "mention_spam", config: config}, content) do
    max_mentions = Map.get(config, "max_mentions", 5)
    action = Map.get(config, "action", "delete")

    mention_count = length(Regex.scan(~r/@\w+/, content))

    if mention_count > max_mentions do
      {:violation, action, "mention_spam"}
    else
      :ok
    end
  end

  defp check_rule(_, _), do: :ok
end
