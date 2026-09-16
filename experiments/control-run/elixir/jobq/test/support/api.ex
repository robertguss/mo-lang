defmodule Jobq.Test.Api do
  @moduledoc "The API over a real socket, for the tests that are about the API."

  alias Jobq.Client

  @doc "One request against the service on `port`, with its body decoded."
  @spec request(:inet.port_number(), String.t(), String.t(), String.t(), String.t() | nil) ::
          {100..599, term()}
  def request(port, token, method, path, body \\ nil) do
    {:ok, status, body} = Client.request({127, 0, 0, 1}, port, token, method, path, body)

    case body do
      "" -> {status, nil}
      body -> {status, JSON.decode!(body)}
    end
  end

  @doc "A raw request, headers and all, for what the client does not say."
  @spec raw(:inet.port_number(), iodata()) :: String.t()
  def raw(port, request) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)
    :ok = :gen_tcp.send(socket, request)
    text = read(socket, "")
    :gen_tcp.close(socket)
    text
  end

  defp read(socket, acc) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, bytes} -> read(socket, acc <> bytes)
      {:error, _reason} -> acc
    end
  end
end
