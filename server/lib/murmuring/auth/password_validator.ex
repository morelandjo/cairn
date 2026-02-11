defmodule Murmuring.Auth.PasswordValidator do
  @moduledoc """
  Validates passwords against common password lists and policy rules.
  Uses an ETS table loaded at startup with a bundled 10k common passwords list.
  """

  @table :common_passwords

  def start_link do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    load_passwords()
    :ignore
  end

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Validates a password against policy rules.
  Returns :ok or {:error, reason}.
  """
  def validate(password, username \\ nil) do
    cond do
      String.length(password) < 10 ->
        {:error, "password must be at least 10 characters"}

      String.length(password) > 128 ->
        {:error, "password must be at most 128 characters"}

      username && String.downcase(password) == String.downcase(username) ->
        {:error, "password cannot be the same as your username"}

      is_common?(password) ->
        {:error, "password is too common"}

      true ->
        :ok
    end
  end

  @doc """
  Checks if a password is in the common passwords list.
  """
  def is_common?(password) do
    case :ets.lookup(@table, String.downcase(password)) do
      [{_, true}] -> true
      [] -> false
    end
  end

  defp load_passwords do
    path = Application.app_dir(:murmuring, "priv/data/common_passwords.txt")

    if File.exists?(path) do
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.each(fn password ->
        :ets.insert(@table, {String.downcase(password), true})
      end)
    end
  end
end
