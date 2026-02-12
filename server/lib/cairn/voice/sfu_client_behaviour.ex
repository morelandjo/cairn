defmodule Murmuring.Voice.SfuClientBehaviour do
  @callback create_room(String.t()) :: {:ok, map()} | {:error, term()}
  @callback destroy_room(String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_rtp_capabilities(String.t()) :: {:ok, map()} | {:error, term()}
  @callback add_peer(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback remove_peer(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback create_send_transport(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback create_recv_transport(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback connect_transport(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback produce(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback consume(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback resume_consumer(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback producer_action(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_producers(String.t(), String.t() | nil) :: {:ok, list()} | {:error, term()}
end
