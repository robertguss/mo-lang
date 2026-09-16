defmodule Jobq.Client do
  @moduledoc """
  One request over a real socket, for `jobq client` and `jobq check`.

  It speaks the same HTTP the service does and reads the answer with OTP's
  packet mode, and it is the only client the check script goes through, so what
  the transcript records is what came back over the wire.
  """

  @connect_timeout 5_000
  @reply_timeout 60_000

  @doc """
  Send one request and return its status and body.

  `body` is the JSON to send, or `nil` for no body. The connection is opened
  and closed around the one request.
  """
  @spec request(
          String.t() | :inet.ip_address(),
          :inet.port_number(),
          String.t(),
          String.t(),
          String.t(),
          String.t() | nil
        ) :: {:ok, 100..599, String.t()} | {:error, term()}
  def request(host, port, token, method, path, body \\ nil) do
    address = if is_binary(host), do: String.to_charlist(host), else: host
    header = host_header(host, port)

    with {:ok, socket} <-
           :gen_tcp.connect(address, port, [:binary, active: false], @connect_timeout) do
      try do
        with :ok <- :gen_tcp.send(socket, frame(header, method, path, token, body)) do
          response(socket)
        end
      after
        :gen_tcp.close(socket)
      end
    end
  end

  defp host_header(host, port) when is_binary(host), do: "#{host}:#{port}"
  defp host_header(host, port) when is_list(host), do: "#{List.to_string(host)}:#{port}"

  defp host_header(host, port) when is_tuple(host),
    do: "#{host |> :inet.ntoa() |> List.to_string()}:#{port}"

  defp frame(host, method, path, token, body) do
    body = body || ""

    [
      method,
      " ",
      path,
      " HTTP/1.1\r\nhost: ",
      host,
      "\r\nauthorization: Bearer ",
      token,
      "\r\ncontent-type: application/json\r\ncontent-length: ",
      Integer.to_string(byte_size(body)),
      "\r\nconnection: close\r\n\r\n",
      body
    ]
  end

  defp response(socket) do
    :ok = :inet.setopts(socket, packet: :http_bin)

    case :gen_tcp.recv(socket, 0, @reply_timeout) do
      {:ok, {:http_response, _version, status, _phrase}} -> headers(socket, status, %{})
      {:ok, other} -> {:error, {:unexpected, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp headers(socket, status, acc) do
    case :gen_tcp.recv(socket, 0, @reply_timeout) do
      {:ok, {:http_header, _length, field, _reserved, value}} ->
        headers(socket, status, Map.put(acc, field |> to_string() |> String.downcase(), value))

      {:ok, :http_eoh} ->
        body(socket, status, acc)

      {:ok, other} ->
        {:error, {:unexpected, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp body(socket, status, headers) do
    :ok = :inet.setopts(socket, packet: :raw)

    case Integer.parse(Map.get(headers, "content-length", "0")) do
      {0, ""} ->
        {:ok, status, ""}

      {length, ""} ->
        case :gen_tcp.recv(socket, length, @reply_timeout) do
          {:ok, body} -> {:ok, status, body}
          {:error, reason} -> {:error, reason}
        end

      _other ->
        {:error, :bad_content_length}
    end
  end
end
