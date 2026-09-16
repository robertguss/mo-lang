defmodule Jobq.Json do
  @moduledoc """
  JSON on OTP 27's `:json`, with ordered objects.

  Encoding takes `{:obj, [{key, value}]}` for an object whose keys keep the
  order they are written in, so every response body and every store record has
  one byte-for-byte shape. Plain maps, lists, binaries, integers, booleans and
  `nil` encode as usual. Decoding is Elixir's `JSON.decode/1`, which refuses
  trailing bytes after the value.
  """

  @type obj :: {:obj, [{String.t(), value()}]}
  @type value :: obj() | String.t() | integer() | float() | boolean() | nil | [value()] | map()

  @doc "Encode a value to a JSON binary. Objects written as `{:obj, kvs}` keep their key order."
  @spec encode(value()) :: String.t()
  def encode(value), do: value |> :json.encode(&encoder/2) |> IO.iodata_to_binary()

  @doc "Decode a JSON binary. Trailing bytes after the value are an error."
  @spec decode(binary()) :: {:ok, term()} | {:error, term()}
  def decode(binary) when is_binary(binary), do: JSON.decode(binary)

  defp encoder({:obj, kvs}, encode) when is_list(kvs),
    do: :json.encode_key_value_list(kvs, encode)

  defp encoder(nil, _encode), do: "null"
  defp encoder(other, encode), do: :json.encode_value(other, encode)
end
