defmodule Jobq.Check do
  @moduledoc """
  `jobq check <dir> <script>`: serve on a free port and play a script of
  `<token> <method> <path> [<json>]` lines through `Jobq.Client`, printing what
  was played and what came back.

  It is the program-level check: a real service, a real socket, a real client,
  and a transcript a test can diff.

  Two lines are not requests. `@retain-ms N` sets the service's `retain_ms`
  before it starts (the last one wins, wherever it stands), and `@sleep N`
  waits N milliseconds on the real clock, so a script can watch a done job
  move to the archive; the sleep is echoed in the transcript.
  """

  alias Jobq.Client
  alias Jobq.Server

  @doc """
  Play `script` against a service on `dir` and print the transcript.

  Returns `:ok`, or `{:error, reason}` if a request could not be made at all.
  """
  @spec run(Path.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def run(dir, script, opts \\ []) do
    ref = Keyword.get(opts, :ref, make_ref())
    device = Keyword.get(opts, :device, :stdio)

    with {:ok, lines} <- read_script(script),
         {:ok, retain} <- retain(lines),
         opts = Keyword.merge(opts, retain),
         {:ok, _pid} <- Server.start_link(Keyword.merge(opts, ref: ref, dir: dir, port: 0)) do
      port = Server.port(ref)

      try do
        play(lines, port, device)
      after
        Server.stop(ref)
      end
    end
  end

  defp read_script(path) do
    case File.read(path) do
      {:ok, text} -> {:ok, text |> String.split("\n") |> Enum.map(&String.trim_trailing/1)}
      {:error, reason} -> {:error, {:script, path, reason}}
    end
  end

  defp retain(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn
      "@retain-ms " <> ms = line, {:ok, acc} ->
        case Integer.parse(ms) do
          {ms, ""} when ms > 0 -> {:cont, {:ok, Keyword.put(acc, :retain_ms, ms)}}
          _other -> {:halt, {:error, {:script_line, line}}}
        end

      _line, acc ->
        {:cont, acc}
    end)
  end

  defp play(lines, port, device) do
    Enum.reduce_while(lines, :ok, fn line, :ok ->
      case step(line, port, device) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp step("", _port, _device), do: :ok
  defp step("#" <> _comment, _port, _device), do: :ok
  defp step("@retain-ms " <> _ms, _port, _device), do: :ok

  defp step("@sleep " <> ms = line, _port, device) do
    case Integer.parse(ms) do
      {ms, ""} when ms >= 0 ->
        IO.puts(device, "> " <> line)
        Process.sleep(ms)

      _other ->
        {:error, {:script_line, line}}
    end
  end

  defp step(line, port, device) do
    case parse(line) do
      {:ok, token, method, path, body} ->
        IO.puts(device, "> " <> line)

        case Client.request({127, 0, 0, 1}, port, token, method, path, body) do
          {:ok, status, ""} ->
            IO.puts(device, "< " <> Integer.to_string(status))
            :ok

          {:ok, status, body} ->
            IO.puts(device, "< " <> Integer.to_string(status) <> " " <> body)
            :ok

          {:error, reason} ->
            {:error, {:request, line, reason}}
        end

      :error ->
        {:error, {:script_line, line}}
    end
  end

  defp parse(line) do
    case String.split(line, " ", parts: 4) do
      [token, method, path, body] -> {:ok, token, method, path, body}
      [token, method, path] -> {:ok, token, method, path, nil}
      _other -> :error
    end
  end
end
