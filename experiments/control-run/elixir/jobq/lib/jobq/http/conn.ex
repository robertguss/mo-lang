defmodule Jobq.Http.Conn do
  @moduledoc """
  One connection: read a request, answer it, read the next one.

  The request line and the headers are parsed by OTP's own HTTP packet mode,
  so this module holds no parser of its own; the body is read by its
  `content-length`. Every read has a deadline. A connection that has sent
  nothing is closed after `:idle_ms`, which is what keeps a client that opens
  sockets and says nothing from holding anything but its own process.
  """

  require Logger

  @type opts :: %{
          ref: term(),
          idle_ms: pos_integer(),
          request_ms: pos_integer(),
          max_body: pos_integer()
        }

  @doc "Serve a connection handed over by an acceptor."
  @spec serve(:gen_tcp.socket(), opts()) :: :ok
  def serve(socket, opts) do
    receive do
      :handover -> loop(socket, opts, opts.idle_ms)
    after
      opts.idle_ms -> :ok
    end

    :gen_tcp.close(socket)
    :ok
  end

  defp loop(socket, opts, timeout) do
    :ok = :inet.setopts(socket, packet: :http_bin, packet_size: 16_384)

    case read_request(socket, opts, timeout) do
      {:ok, request} ->
        {status, body} = Jobq.Router.route(request, opts.ref)
        keep? = keep_alive?(request)
        send_response(socket, status, body, keep?)
        if keep?, do: loop(socket, opts, opts.idle_ms), else: :ok

      {:error, :closed} ->
        :ok

      {:error, :timeout} ->
        :ok

      {:error, status, message} ->
        send_response(socket, status, Jobq.Json.encode({:obj, [{"error", message}]}), false)
        :ok
    end
  end

  defp read_request(socket, opts, timeout) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, {:http_request, method, {:abs_path, path}, version}} ->
        read_headers(socket, opts, %{
          method: normalize_method(method),
          path: path,
          version: version,
          headers: %{},
          body: ""
        })

      {:ok, {:http_request, _method, _uri, _version}} ->
        {:error, 400, "the request target must be an absolute path"}

      {:ok, {:http_error, _line}} ->
        {:error, 400, "malformed request"}

      {:ok, _other} ->
        {:error, 400, "malformed request"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_headers(socket, opts, request) do
    case :gen_tcp.recv(socket, 0, opts.request_ms) do
      {:ok, {:http_header, _length, field, _reserved, value}} ->
        name = field |> to_string() |> String.downcase()
        read_headers(socket, opts, put_in(request.headers[name], value))

      {:ok, :http_eoh} ->
        read_body(socket, opts, request)

      {:ok, {:http_error, _line}} ->
        {:error, 400, "malformed header"}

      {:ok, _other} ->
        {:error, 400, "malformed header"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_body(socket, opts, request) do
    :ok = :inet.setopts(socket, packet: :raw)

    if Map.has_key?(request.headers, "transfer-encoding") do
      {:error, 400, "the body must carry a content-length"}
    else
      read_sized_body(socket, opts, request)
    end
  end

  defp read_sized_body(socket, opts, request) do
    case content_length(request) do
      {:ok, 0} ->
        {:ok, request}

      {:ok, length} when length > opts.max_body ->
        {:error, 400, "the body is too large"}

      {:ok, length} ->
        case :gen_tcp.recv(socket, length, opts.request_ms) do
          {:ok, body} -> {:ok, %{request | body: body}}
          {:error, reason} -> {:error, reason}
        end

      :error ->
        {:error, 400, "content-length must be a number"}
    end
  end

  defp content_length(request) do
    case Map.fetch(request.headers, "content-length") do
      :error ->
        {:ok, 0}

      {:ok, value} ->
        case Integer.parse(value) do
          {length, ""} when length >= 0 -> {:ok, length}
          _ -> :error
        end
    end
  end

  defp normalize_method(method) when is_atom(method), do: Atom.to_string(method)
  defp normalize_method(method) when is_binary(method), do: method

  defp keep_alive?(%{version: {1, 1}, headers: headers}),
    do: String.downcase(Map.get(headers, "connection", "keep-alive")) != "close"

  defp keep_alive?(%{headers: headers}),
    do: String.downcase(Map.get(headers, "connection", "close")) == "keep-alive"

  defp send_response(socket, status, body, keep?) do
    body = body || ""

    head = [
      "HTTP/1.1 ",
      Integer.to_string(status),
      " ",
      reason_phrase(status),
      "\r\ncontent-type: application/json\r\ncontent-length: ",
      Integer.to_string(IO.iodata_length(body)),
      "\r\nconnection: ",
      if(keep?, do: "keep-alive", else: "close"),
      "\r\n\r\n"
    ]

    case :gen_tcp.send(socket, [head, body]) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp reason_phrase(200), do: "OK"
  defp reason_phrase(201), do: "Created"
  defp reason_phrase(204), do: "No Content"
  defp reason_phrase(400), do: "Bad Request"
  defp reason_phrase(401), do: "Unauthorized"
  defp reason_phrase(404), do: "Not Found"
  defp reason_phrase(405), do: "Method Not Allowed"
  defp reason_phrase(409), do: "Conflict"
  defp reason_phrase(503), do: "Service Unavailable"
end
