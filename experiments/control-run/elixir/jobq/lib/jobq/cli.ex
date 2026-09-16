defmodule Jobq.CLI do
  @moduledoc """
  The five commands.

      jobq serve <dir> [--port N] [--max-restarts K] [--restart-window S] [--crash-every N]
                [--retain-ms N]
      jobq compact <dir>
      jobq verify <dir>
      jobq client <host> <port> <token> <method> <path> [<json>]
      jobq check <dir> <script>

  Exit 2 on a usage error, 1 when the directory cannot be opened or the port
  cannot be bound, and 70 when `serve`'s board has failed more than
  `--max-restarts` times (default 5) inside `--restart-window` seconds
  (default 60). `--crash-every N` (default 0, never) fails the board on every
  N-th write it applies, to rehearse the restart in staging. `--retain-ms N`
  (default 86,400,000, a day; 1,000 to 2,678,400,000) is how long a done or
  dead job stays on the board before it is moved to the archive.

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
  usage: jobq serve <dir> [--port N] [--max-restarts K] [--restart-window S] [--crash-every N]
                    [--retain-ms N]
         jobq compact <dir>
         jobq verify <dir>
         jobq client <host> <port> <token> <method> <path> [<json>]
         jobq check <dir> <script>
  """

  @serve_defaults [
    port: 7900,
    max_restarts: 5,
    restart_window: 60,
    crash_every: 0,
    retain_ms: 86_400_000
  ]

  # A window of 0 seconds is not one the supervisor can keep, so it starts at 1.
  @serve_flags %{
    "--port" => {:port, 0, 65_535},
    "--max-restarts" => {:max_restarts, 0, 1_000_000},
    "--restart-window" => {:restart_window, 1, 86_400 * 365},
    "--crash-every" => {:crash_every, 0, 1_000_000_000},
    "--retain-ms" => {:retain_ms, 1_000, 2_678_400_000}
  }

  @doc "The escript's entry point."
  @spec main([String.t()]) :: no_return()
  def main(argv) do
    System.halt(run(argv))
  end

  @doc "Run one command and return its exit status."
  @spec run([String.t()]) :: 0 | 1 | 2 | 70
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
    with {:ok, options} <- serve_options(rest, @serve_defaults),
         :ok <- open_dir(dir),
         {:ok, _log} <- read_dir(dir) do
      # The tree is linked to this process: trapping exits is what turns a
      # listener that cannot bind, or a tree that gives up later, into a
      # message and an exit status rather than a dead command.
      Process.flag(:trap_exit, true)

      case Server.start_link([dir: dir] ++ options) do
        {:ok, pid} ->
          IO.puts("jobq: serving #{dir} on port #{Server.port(:default)}")

          receive do
            {:EXIT, ^pid, reason} -> stopped(reason, options)
          end

        {:error, reason} ->
          fail(reason)
      end
    else
      {:usage, message} -> usage_error(message)
      {:error, reason} -> fail(reason)
    end
  end

  # The board used its budget, and the service stopped on its own: the log is
  # whole, since the store wrote nothing more once the board was down.
  defp stopped(:shutdown, options) do
    IO.write(
      :stderr,
      "jobq: the service failed more than #{options[:max_restarts]} time(s) " <>
        "inside #{options[:restart_window]} second(s), and stopped\n"
    )

    70
  end

  defp stopped(reason, _options), do: fail({:stopped, reason})

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
         {:ok, %{jobs: jobs, next: next, archived: archived}} <- read_dir(dir) do
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
           end)) <> "; next id j_#{next}; archived #{map_size(archived)}"
      )

      0
    else
      {:error, reason} -> fail(reason)
    end
  end

  # The folder as the service will read it, with the record that refuses it
  # named by the folder it is in.
  defp read_dir(dir) do
    case Store.open(dir) do
      {:ok, folder} -> {:ok, folder}
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

  # `serve`'s options, in any order, the last of a name winning.
  defp serve_options([], options), do: {:ok, options}

  defp serve_options([flag, value | rest], options) when is_map_key(@serve_flags, flag) do
    {key, min, max} = Map.fetch!(@serve_flags, flag)

    case number(value, flag, min, max) do
      {:ok, number} -> serve_options(rest, Keyword.put(options, key, number))
      {:usage, message} -> {:usage, message}
    end
  end

  defp serve_options(_rest, _options), do: {:usage, "unknown option"}

  defp integer(value, name), do: number(value, name, 0, 65_535)

  defp number(value, name, min, max) do
    case Integer.parse(value) do
      {number, ""} when number >= min and number <= max -> {:ok, number}
      _other -> {:usage, "#{name} must be a number from #{min} to #{max}"}
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
  defp describe({:corrupt_archive, line}), do: "the archive is corrupt at line #{line}"

  defp describe({:record, dir, key, rule}), do: "#{dir}: record #{key}: #{rule}"
  defp describe({:stopped, reason}), do: "the service stopped: #{describe(reason)}"
  defp describe({:script, path, reason}), do: "cannot read #{path}: #{:file.format_error(reason)}"
  defp describe({:script_line, line}), do: "cannot read the script line: #{line}"
  defp describe({:request, line, reason}), do: "request failed (#{line}): #{inspect(reason)}"
  defp describe(reason), do: inspect(reason)
end
