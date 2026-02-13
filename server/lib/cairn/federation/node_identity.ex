defmodule Cairn.Federation.NodeIdentity do
  @moduledoc """
  Manages the node's Ed25519 signing key pair for federation.

  On startup, loads the key from disk or generates a new pair.
  The key persists across restarts so the node maintains a stable identity.
  """

  use GenServer

  require Logger

  # ── Client API ──

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the Ed25519 public key as raw 32 bytes."
  @spec public_key() :: binary()
  def public_key do
    GenServer.call(__MODULE__, :public_key)
  end

  @doc "Returns the Ed25519 public key as a base64-encoded string."
  @spec public_key_base64() :: String.t()
  def public_key_base64 do
    Base.encode64(public_key())
  end

  @doc "Returns the node ID — SHA-256 fingerprint of the public key, hex-encoded."
  @spec node_id() :: String.t()
  def node_id do
    GenServer.call(__MODULE__, :node_id)
  end

  @doc "Returns the previous public key (during rotation grace period), or nil."
  @spec previous_public_key_base64() :: String.t() | nil
  def previous_public_key_base64 do
    GenServer.call(__MODULE__, :previous_public_key_base64)
  end

  @doc "Signs a message with the node's Ed25519 private key."
  @spec sign(binary()) :: binary()
  def sign(message) when is_binary(message) do
    GenServer.call(__MODULE__, {:sign, message})
  end

  @doc """
  Rotate the node's signing key pair.
  The old key is retained for a grace period (default 7 days).
  """
  @spec rotate_key() :: :ok
  def rotate_key do
    GenServer.call(__MODULE__, :rotate_key)
  end

  @doc """
  Verifies a signature against a message using the given public key.
  Stateless — does not require the GenServer.
  """
  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(message, signature, public_key)
      when is_binary(message) and is_binary(signature) and is_binary(public_key) do
    :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
  rescue
    _ -> false
  end

  # ── GenServer Callbacks ──

  @impl true
  def init(opts) do
    key_path = Keyword.get(opts, :key_path) || default_key_path()

    case load_or_generate_key(key_path) do
      {:ok, private_key, public_key} ->
        node_id = :crypto.hash(:sha256, public_key) |> Base.encode16(case: :lower)

        Logger.info(
          "Federation node identity loaded (node_id: #{String.slice(node_id, 0, 16)}...)"
        )

        # Check for previous key (rotation grace period)
        prev = load_previous_key(key_path)

        {:ok,
         %{
           private_key: private_key,
           public_key: public_key,
           node_id: node_id,
           key_path: key_path,
           previous_public_key: prev
         }}

      {:error, reason} ->
        Logger.error("Failed to initialize node identity: #{inspect(reason)}")
        {:stop, {:key_init_failed, reason}}
    end
  end

  @impl true
  def handle_call(:public_key, _from, state) do
    {:reply, state.public_key, state}
  end

  @impl true
  def handle_call(:node_id, _from, state) do
    {:reply, state.node_id, state}
  end

  @impl true
  def handle_call(:previous_public_key_base64, _from, state) do
    result =
      case state[:previous_public_key] do
        nil -> nil
        key -> Base.encode64(key)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:sign, message}, _from, state) do
    signature = :crypto.sign(:eddsa, :none, message, [state.private_key, :ed25519])
    {:reply, signature, state}
  end

  # sobelow_skip ["Traversal.FileModule"]
  @impl true
  def handle_call(:rotate_key, _from, state) do
    key_path = state.key_path

    # Save current key as previous
    prev_path = key_path <> ".prev"
    data = :erlang.term_to_binary({state.private_key, state.public_key})
    File.write!(prev_path, data)

    # Generate new key
    {new_public, new_private} = :crypto.generate_key(:eddsa, :ed25519)
    new_data = :erlang.term_to_binary({new_private, new_public})
    File.write!(key_path, new_data)
    File.chmod!(key_path, 0o600)

    new_node_id = :crypto.hash(:sha256, new_public) |> Base.encode16(case: :lower)

    Logger.info("Federation key rotated (new node_id: #{String.slice(new_node_id, 0, 16)}...)")

    new_state = %{
      state
      | private_key: new_private,
        public_key: new_public,
        node_id: new_node_id,
        previous_public_key: state.public_key
    }

    {:reply, :ok, new_state}
  end

  # ── Private ──

  defp default_key_path do
    Application.get_env(:cairn, :federation, [])
    |> Keyword.get(:node_key_path, Path.join(:code.priv_dir(:cairn), "keys/node_ed25519.key"))
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp load_previous_key(path) do
    prev_path = path <> ".prev"

    if File.exists?(prev_path) do
      case File.read(prev_path) do
        {:ok, data} ->
          try do
            case :erlang.binary_to_term(data, [:safe]) do
              {_private_key, public_key} when is_binary(public_key) -> public_key
              _ -> nil
            end
          rescue
            _ -> nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp load_or_generate_key(path) do
    if File.exists?(path) do
      load_key(path)
    else
      generate_and_save_key(path)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp load_key(path) do
    case File.read(path) do
      {:ok, data} ->
        try do
          case :erlang.binary_to_term(data, [:safe]) do
            {private_key, public_key} when is_binary(private_key) and is_binary(public_key) ->
              {:ok, private_key, public_key}

            _ ->
              {:error, :invalid_key_format}
          end
        rescue
          ArgumentError -> {:error, :invalid_key_format}
        end

      {:error, reason} ->
        {:error, {:read_failed, reason}}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp generate_and_save_key(path) do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    data = :erlang.term_to_binary({private_key, public_key})
    File.write!(path, data)

    # Set 0600 permissions (owner read/write only)
    File.chmod!(path, 0o600)

    Logger.info("Generated new Ed25519 federation key at #{path}")
    {:ok, private_key, public_key}
  end
end
