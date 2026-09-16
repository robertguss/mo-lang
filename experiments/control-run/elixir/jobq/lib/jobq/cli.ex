defmodule Jobq.CLI do
  @moduledoc """
  The four commands.

      jobq serve <dir> [--port N]      default port 7900
      jobq compact <dir>
      jobq client <host> <port> <token> <method> <path> [<json>]
      jobq check <dir> <script>

  Exit 2 on a usage error, 1 when the directory cannot be opened or the port
  cannot be bound.
  """

  alias Jobq.Client
  alias Jobq.Server
  alias Jobq.Store

  @usage """
  usage: jobq serve <dir> [--port N]
         jobq compact <dir>
         jobq client <host> <port> <token> <method> <path> [<json>]
         jobq check <dir> <script>
  """

  @default_port 7900

  @doc "The escript's entry point."
  @spec main([String.t()]) :: no_return()
  def main(argv) do
    System.halt(run(argv))
  end

  @doc "Run one command and return its exit status."
  @spec run([String.t()]) :: 0 | 1 | 2
  def run(["serve", dir | rest]), do: serve(dir, rest)
  def run(["compact", dir]), do: compact(dir)
  def run(["client", host, port, token, method, path | rest]),
    do: client(host, port, token, method, path, rest)

  def run(["check", dir, script]), do: check(dir, script)
  def run(_argv), do: usage()

  defp usage do
    IO.write(:stderr, @usage)
    2
  end

  defp serve(dir, rest) do
    with {:ok, port} <- port_option(rest),
         :ok <- open_dir(dir) do
      case Server.start_link(dir: dir, port: port) do
        {:ok, _pid} ->
          IO.puts("jobq: serving #{dir} on port #{Server.port(:default)}")
          Process.sleep(:infinity)
          0

        {:error, reason} ->
          fail(reason)
      end
    else
      {:usage, message} -> usage_error(message)
      {:error, reason} -> fail(reason)
    end
  end

  defp compact(dir) do
    with :ok <- open_dir(dir) do
      case Store.compact(dir) do
        {:ok, count} ->
          IO.puts("jobq: compacted #{dir} to #{count} job(s)")
          0

        {:error, reason} ->
          fail(reason)
      end
    else
      {:error, reason} -> fail(reason)
    end
  end

  defp client(host, port, token, method, path, rest) do
    body =
      case rest do
        [] -> nil
        [json] -> json
        _more -> nil
      end

    with {:ok, port} <- integer(port, "port") do
      case Client.request(host, port, token, method, path, body) do
        {:ok, status, ""} ->
          IO.puts(Integer.to_string(status))
          0

        {:ok, status, body} ->
          IO.puts(Integer.to_string(status) <> " " <> body)
          0

        {:error, reason} ->
          fail(reason)
      end
    else
      {:usage, message} -> usage_error(message)
    end
  end

  defp check(dir, script) do
    with :ok <- open_dir(dir) do
      case Jobq.Check.run(dir, script) do
        :ok -> 0
        {:error, reason} -> fail(reason)
      end
    else
      {:error, reason} -> fail(reason)
    end
  end

  defp port_option([]), do: {:ok, @default_port}
  defp port_option(["--port", value]), do: integer(value, "--port")
  defp port_option(_rest), do: {:usage, "unknown option"}

  defp integer(value, name) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 and number <= 65_535 -> {:ok, number}
      _other -> {:usage, "#{name} must be a number from 0 to 65535"}
    end
  end

  defp open_dir(dir) do
    with :ok <- File.mkdir_p(dir),
         true <- File.dir?(dir),
         {:ok, _files} <- File.ls(dir) do
      :ok
    else
      false -> {:error, {:dir, dir, :enotdir}}
      {:error, reason} -> {:error, {:dir, dir, reason}}
    end
  end

  defp usage_error(message) do
    IO.write(:stderr, "jobq: #{message}\n")
    IO.write(:stderr, @usage)
    2
  end

  defp fail(reason) do
    IO.write(:stderr, "jobq: #{describe(reason)}\n")
    1
  end

  defp describe({:dir, dir, reason}), do: "cannot open #{dir}: #{:file.format_error(reason)}"

  defp describe({:bind, port, reason}),
    do: "cannot bind port #{port}: #{:file.format_error(reason)}"

  defp describe({:shutdown, {:failed_to_start_child, _child, reason}}), do: describe(reason)
  defp describe({:open, path, reason}), do: "cannot open #{path}: #{:file.format_error(reason)}"
  defp describe({:corrupt, line}), do: "the log is corrupt at line #{line}"
  defp describe({:script, path, reason}), do: "cannot read #{path}: #{:file.format_error(reason)}"
  defp describe({:script_line, line}), do: "cannot read the script line: #{line}"
  defp describe({:request, line, reason}), do: "request failed (#{line}): #{inspect(reason)}"
  defp describe(reason), do: inspect(reason)
end
