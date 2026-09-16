defmodule Jobq.CLI do
  @moduledoc """
  The five commands.

      jobq serve <dir> [--port N]      default port 7900
      jobq compact <dir>
      jobq verify <dir>
      jobq client <host> <port> <token> <method> <path> [<json>]
      jobq check <dir> <script>

  Exit 2 on a usage error, 1 when the directory cannot be opened or the port
  cannot be bound.

  `serve`, `compact`, and `verify` all read the folder before they do anything
  else, and all refuse an ill-formed record the same way: one line naming the
  record's key and the rule it breaks, and exit 1. `serve` refuses before it
  binds the port, so a folder with a record the API could never have produced
  is never served.
  """

  alias Jobq.Client
  alias Jobq.Job
  alias Jobq.Server
  alias Jobq.Store

  @usage """
  usage: jobq serve <dir> [--port N]
         jobq compact <dir>
         jobq verify <dir>
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
  def run(["verify", dir]), do: verify(dir)

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
         :ok <- open_dir(dir),
         {:ok, _log} <- read_dir(dir) do
      # The tree is linked to this process: trapping exits is what turns a
      # listener that cannot bind, or a tree that gives up later, into a
      # message and an exit status rather than a dead command.
      Process.flag(:trap_exit, true)

      case Server.start_link(dir: dir, port: port) do
        {:ok, pid} ->
          IO.puts("jobq: serving #{dir} on port #{Server.port(:default)}")

          receive do
            {:EXIT, ^pid, reason} -> fail({:stopped, reason})
          end

        {:error, reason} ->
          fail(reason)
      end
    else
      {:usage, message} -> usage_error(message)
      {:error, reason} -> fail(reason)
    end
  end

  defp compact(dir) do
    with :ok <- open_dir(dir),
         {:ok, _log} <- read_dir(dir) do
      report_compact(dir, Store.compact(dir))
    else
      {:error, reason} -> fail(reason)
    end
  end

  defp verify(dir) do
    with :ok <- open_dir(dir),
         {:ok, {jobs, next}} <- read_dir(dir) do
      counts =
        jobs
        |> Map.values()
        |> Enum.frequencies_by(& &1.state)

      IO.puts(
        "#{map_size(jobs)} jobs: " <>
          (Job.state_names()
           |> Enum.map_join(", ", fn name ->
             {:ok, state} = Job.parse_state(name)
             "#{name} #{Map.get(counts, state, 0)}"
           end)) <> "; next id j_#{next}"
      )

      0
    else
      {:error, reason} -> fail(reason)
    end
  end

  # The folder as the service will read it, with the record that refuses it
  # named by the folder it is in.
  defp read_dir(dir) do
    case Store.read(dir) do
      {:ok, log} -> {:ok, log}
      {:error, {:record, key, rule}} -> {:error, {:record, dir, key, rule}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp report_compact(dir, {:ok, count}) do
    IO.puts("jobq: compacted #{dir} to #{count} job(s)")
    0
  end

  defp report_compact(_dir, {:error, reason}), do: fail(reason)

  defp client(host, port, token, method, path, rest) do
    body =
      case rest do
        [] -> nil
        [json] -> json
        _more -> nil
      end

    case integer(port, "port") do
      {:ok, port} -> report_request(Client.request(host, port, token, method, path, body))
      {:usage, message} -> usage_error(message)
    end
  end

  defp report_request({:ok, status, ""}) do
    IO.puts(Integer.to_string(status))
    0
  end

  defp report_request({:ok, status, body}) do
    IO.puts(Integer.to_string(status) <> " " <> body)
    0
  end

  defp report_request({:error, reason}), do: fail(reason)

  defp check(dir, script) do
    Process.flag(:trap_exit, true)

    with :ok <- open_dir(dir),
         {:ok, _log} <- read_dir(dir),
         :ok <- Jobq.Check.run(dir, script) do
      0
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

  defp describe({:record, dir, key, rule}), do: "#{dir}: record #{key}: #{rule}"
  defp describe({:stopped, reason}), do: "the service stopped: #{describe(reason)}"
  defp describe({:script, path, reason}), do: "cannot read #{path}: #{:file.format_error(reason)}"
  defp describe({:script_line, line}), do: "cannot read the script line: #{line}"
  defp describe({:request, line, reason}), do: "request failed (#{line}): #{inspect(reason)}"
  defp describe(reason), do: inspect(reason)
end
