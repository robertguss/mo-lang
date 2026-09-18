defmodule Jobq.Bench do
  @moduledoc """
  `jobq bench <dir>`: the speed budget's measurement, the round's `measure.py`
  in the program's own hands.

  It starts a service on a free port in `dir`, creates `jobs` jobs from eight
  producers, leases and acks them from one worker and then from `workers`
  concurrent workers (ten seconds each, or until the queues are empty),
  restarts the service, and prints one line per number: creates a second,
  pairs a second at 1 and at `workers` workers, the seconds from the restart
  to a `200` on `/health`, and the resident memory after the pairs. Every
  client holds one keep-alive connection; payloads are 100 bytes, spread over
  four queues, and worker `i` leases from queue `i mod 4`, as `measure.py`'s
  do.

  The service is a separate OS process started from a command, by default this
  escript's own `serve`, so the same bench measures another build of the
  program (`--serve '<cmd> serve {dir} --port {port}'`), which is how the
  budget compares change 6 with change 3 on one machine.
  """

  alias Jobq.Json

  @queues 4
  @producers 8
  @payload String.duplicate("x", 100)

  @typedoc "A running service: its port and the functions that stop it and read its memory."
  @type service :: %{
          port: :inet.port_number(),
          stop: (-> :ok),
          rss_kib: (-> non_neg_integer())
        }

  @typedoc "Starts a service on `dir` at `port`."
  @type starter :: (Path.t(), :inet.port_number() -> {:ok, service()} | {:error, term()})

  @doc """
  Run the bench on `dir` and print its lines to `:device` (default stdout).

  Options: `:jobs` (default 30,000), `:workers` (default 32), `:seconds` a
  pairs phase may run (default 10), `:up_ms` the service has to answer
  `/health` at its first start (default 20,000; `{:error, {:no_health, port}}`
  after it), and `:serve`, the command template, or `:start`, a
  `t:starter/0` a test hands in instead.
  """
  @spec run(Path.t(), keyword()) :: :ok | {:error, term()}
  def run(dir, opts) do
    jobs = Keyword.get(opts, :jobs, 30_000)
    workers = Keyword.get(opts, :workers, 32)
    seconds = Keyword.get(opts, :seconds, 10)
    device = Keyword.get(opts, :device, :stdio)
    start = Keyword.get_lazy(opts, :start, fn -> external(Keyword.fetch!(opts, :serve)) end)
    port = free_port()

    say(device, "load average before: #{load_average()}")
    started = now_ms()

    with {:ok, service} <- start.(dir, port),
         :ok <- wait_health(port, Keyword.get(opts, :up_ms, 20_000)) do
      say(device, "up in #{secs(now_ms() - started)} s; rss empty #{mib(service.rss_kib.())} MiB")
      measure(service, %{dir: dir, jobs: jobs, workers: workers, seconds: seconds}, device)
      restart(start, service, dir, port, device)
    end
  end

  defp measure(service, run, device) do
    {count, elapsed, errors} = creates(service.port, run.jobs)

    say(
      device,
      "creates/s: #{rate(count, elapsed)} (#{count} in #{secs(elapsed)} s, errors #{errors})"
    )

    for workers <- [1, run.workers] do
      {count, elapsed, errors} = pairs(service.port, workers, run.seconds)

      say(
        device,
        "pairs/s at #{workers} worker(s): #{rate(count, elapsed)} " <>
          "(#{count} in #{secs(elapsed)} s, errors #{errors})"
      )
    end

    say(device, "rss after pairs: #{mib(service.rss_kib.())} MiB")
  end

  defp restart(start, service, dir, port, device) do
    :ok = service.stop.()
    bytes = folder_bytes(dir)
    started = now_ms()

    with {:ok, again} <- start.(dir, port),
         :ok <- wait_health(port, 300_000) do
      took = now_ms() - started
      rss = again.rss_kib.()
      :ok = again.stop.()

      say(
        device,
        "restart to /health: #{secs(took)} s (a #{div(bytes, 1_000_000)} MB folder); " <>
          "rss #{mib(rss)} MiB"
      )
    end
  end

  # The load

  defp creates(port, jobs) do
    per = div(jobs, @producers)
    started = now_ms()

    errors =
      1..@producers
      |> Enum.map(fn i -> Task.async(fn -> produce(port, i, per) end) end)
      |> Enum.map(&Task.await(&1, :infinity))
      |> Enum.sum()

    {per * @producers - errors, now_ms() - started, errors}
  end

  defp produce(port, i, per) do
    conn = connect(port)

    Enum.reduce(0..(per - 1)//1, 0, fn k, errors ->
      body = ~s({"queue":"q#{rem(k, @queues)}","payload":"#{@payload}","max_tries":3})

      case request(conn, "p#{i}", "POST", "/jobs", body) do
        {201, _body} -> errors
        _other -> errors + 1
      end
    end)
  end

  defp pairs(port, workers, seconds) do
    deadline = now_ms() + seconds * 1_000
    started = now_ms()

    results =
      0..(workers - 1)
      |> Enum.map(fn i -> Task.async(fn -> work(connect(port), i, deadline, {0, 0}) end) end)
      |> Enum.map(&Task.await(&1, :infinity))

    elapsed = now_ms() - started

    {results |> Enum.map(&elem(&1, 0)) |> Enum.sum(), elapsed,
     results |> Enum.map(&elem(&1, 1)) |> Enum.sum()}
  end

  defp work(conn, i, deadline, {done, errors} = acc) do
    if now_ms() >= deadline do
      acc
    else
      case request(
             conn,
             "w#{i}",
             "POST",
             "/queues/q#{rem(i, @queues)}/lease",
             ~s({"lease_ms":60000})
           ) do
        {200, body} -> work(conn, i, deadline, ack(conn, i, body, acc))
        {204, _body} -> acc
        _other -> work(conn, i, deadline, {done, errors + 1})
      end
    end
  end

  defp ack(conn, i, body, {done, errors}) do
    {:ok, %{"id" => id}} = Json.decode(body)

    case request(conn, "w#{i}", "POST", "/jobs/#{id}/ack", nil) do
      {200, _body} -> {done + 1, errors}
      _other -> {done, errors + 1}
    end
  end

  # One keep-alive connection per client, opened again after an error, as
  # `measure.py`'s clients do.

  defp connect(port) do
    close()
    %{port: port}
  end

  defp request(conn, token, method, path, body, tries \\ 3)
  defp request(_conn, _token, _method, _path, _body, 0), do: {:error, :tries}

  defp request(conn, token, method, path, body, tries) do
    with {:ok, socket} <- socket(conn.port),
         :ok <- :gen_tcp.send(socket, frame(token, method, path, body)),
         {:ok, status, reply} <- response(socket) do
      {status, reply}
    else
      {:error, _reason} ->
        close()
        request(conn, token, method, path, body, tries - 1)
    end
  end

  defp socket(port) do
    case Process.get(:bench_socket) do
      nil ->
        with {:ok, socket} <-
               :gen_tcp.connect(
                 {127, 0, 0, 1},
                 port,
                 [:binary, active: false, nodelay: true],
                 5_000
               ) do
          Process.put(:bench_socket, socket)
          {:ok, socket}
        end

      socket ->
        {:ok, socket}
    end
  end

  defp close do
    case Process.put(:bench_socket, nil) do
      nil -> :ok
      socket -> :gen_tcp.close(socket)
    end
  end

  defp frame(token, method, path, body) do
    body = body || ""

    [
      method,
      " ",
      path,
      " HTTP/1.1\r\nhost: bench\r\nauthorization: Bearer ",
      token,
      "\r\ncontent-type: application/json\r\ncontent-length: ",
      Integer.to_string(byte_size(body)),
      "\r\n\r\n",
      body
    ]
  end

  defp response(socket) do
    :ok = :inet.setopts(socket, packet: :http_bin)

    with {:ok, {:http_response, _version, status, _phrase}} <- :gen_tcp.recv(socket, 0, 60_000),
         {:ok, headers} <- headers(socket, %{}),
         :ok <- :inet.setopts(socket, packet: :raw),
         {:ok, body} <- body(socket, Map.get(headers, "content-length", "0")) do
      if Map.get(headers, "connection") == "close", do: close()
      {:ok, status, body}
    else
      {:ok, other} -> {:error, {:unexpected, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp headers(socket, acc) do
    case :gen_tcp.recv(socket, 0, 60_000) do
      {:ok, {:http_header, _length, field, _reserved, value}} ->
        headers(
          socket,
          Map.put(acc, field |> to_string() |> String.downcase(), String.downcase(value))
        )

      {:ok, :http_eoh} ->
        {:ok, acc}

      other ->
        other
    end
  end

  defp body(_socket, "0"), do: {:ok, ""}
  defp body(socket, length), do: :gen_tcp.recv(socket, String.to_integer(length), 60_000)

  # The service as an OS process

  @doc """
  A `t:starter/0` that runs `template` through `/bin/sh` with `{dir}` and
  `{port}` filled in: the service is that process, stopped with `SIGTERM`
  (and `SIGKILL` ten seconds later), and its memory is the largest resident
  set of the process and its descendants.
  """
  @spec external(String.t()) :: starter()
  def external(template) do
    fn dir, port ->
      command =
        template
        |> String.replace("{dir}", quote_arg(dir))
        |> String.replace("{port}", Integer.to_string(port))

      os =
        Port.open({:spawn_executable, "/bin/sh"}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: ["-c", "exec " <> command]
        ])

      {:os_pid, pid} = Port.info(os, :os_pid)
      {:ok, %{port: port, stop: fn -> stop_os(os, pid) end, rss_kib: fn -> rss_kib(pid) end}}
    end
  end

  @doc "The default command: this escript's own `serve`."
  @spec own_serve() :: String.t()
  def own_serve do
    path = :escript.script_name() |> List.to_string() |> Path.expand()
    quote_arg(path) <> " serve {dir} --port {port}"
  end

  defp quote_arg(text), do: "'" <> String.replace(text, "'", ~S('\'')) <> "'"

  defp stop_os(os, pid) do
    _ = System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)

    receive do
      {^os, {:exit_status, _status}} -> :ok
    after
      10_000 ->
        _ = System.cmd("kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)

        receive do
          {^os, {:exit_status, _status}} -> :ok
        end
    end
  end

  defp rss_kib(pid) do
    {out, 0} = System.cmd("ps", ["-e", "-o", "pid=,ppid=,rss="])

    rows =
      out
      |> String.split("\n", trim: true)
      |> Enum.map(fn line ->
        [p, pp, rss] = line |> String.split() |> Enum.map(&String.to_integer/1)
        {p, pp, rss}
      end)

    tree = descendants(rows, [pid], MapSet.new([pid]))

    rows
    |> Enum.filter(fn {p, _pp, _rss} -> p in tree end)
    |> Enum.map(&elem(&1, 2))
    |> Enum.max(fn -> 0 end)
  end

  defp descendants(_rows, [], seen), do: seen

  defp descendants(rows, frontier, seen) do
    kids = for {p, pp, _rss} <- rows, pp in frontier, p not in seen, do: p
    descendants(rows, kids, MapSet.union(seen, MapSet.new(kids)))
  end

  # Small things

  defp wait_health(port, within), do: wait_health(port, within, now_ms())

  defp wait_health(port, within, started) do
    case Jobq.Client.request({127, 0, 0, 1}, port, "bench", "GET", "/health") do
      {:ok, 200, _body} ->
        :ok

      _other ->
        if now_ms() - started > within do
          {:error, {:no_health, port}}
        else
          Process.sleep(20)
          wait_health(port, within, started)
        end
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp folder_bytes(dir) do
    dir
    |> File.ls!()
    |> Enum.map(fn name -> File.stat!(Path.join(dir, name)).size end)
    |> Enum.sum()
  end

  defp load_average do
    case File.read("/proc/loadavg") do
      {:ok, text} -> text |> String.split() |> Enum.take(3) |> Enum.join(" ")
      {:error, _reason} -> "unknown"
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
  defp rate(_count, 0), do: 0
  defp rate(count, ms), do: round(count * 1_000 / ms)
  defp secs(ms), do: :erlang.float_to_binary(ms / 1_000, decimals: 2)
  defp mib(kib), do: :erlang.float_to_binary(kib / 1_024, decimals: 1)
  defp say(device, line), do: IO.puts(device, line)
end
