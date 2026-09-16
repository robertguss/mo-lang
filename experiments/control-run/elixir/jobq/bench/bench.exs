# The bench client: a real service, real sockets, one keep-alive connection per
# worker. See bench/README.md.

defmodule Bench.Conn do
  @moduledoc false

  def open(port) do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, nodelay: true], 5_000)

    socket
  end

  def request(socket, token, method, path, body \\ nil) do
    body = body || ""

    frame = [
      method,
      " ",
      path,
      " HTTP/1.1\r\nhost: bench\r\nauthorization: Bearer ",
      token,
      "\r\ncontent-length: ",
      Integer.to_string(byte_size(body)),
      "\r\nconnection: keep-alive\r\n\r\n",
      body
    ]

    :ok = :gen_tcp.send(socket, frame)
    :ok = :inet.setopts(socket, packet: :http_bin)
    {:ok, {:http_response, _version, status, _phrase}} = :gen_tcp.recv(socket, 0, 60_000)
    {status, headers(socket, %{})}
  end

  defp headers(socket, acc) do
    case :gen_tcp.recv(socket, 0, 60_000) do
      {:ok, {:http_header, _length, field, _reserved, value}} ->
        headers(socket, Map.put(acc, field |> to_string() |> String.downcase(), value))

      {:ok, :http_eoh} ->
        body(socket, acc)
    end
  end

  defp body(socket, headers) do
    :ok = :inet.setopts(socket, packet: :raw)

    case String.to_integer(Map.get(headers, "content-length", "0")) do
      0 -> ""
      length -> with({:ok, bytes} <- :gen_tcp.recv(socket, length, 60_000), do: bytes)
    end
  end
end

defmodule Bench do
  @moduledoc false

  alias Bench.Conn

  @queue "bench"

  def main(argv) do
    {options, names} = OptionParser.parse!(argv, strict: [jobs: :integer])
    jobs = Keyword.get(options, :jobs, 20_000)
    names =
      if names == [],
        do: ~w(throughput expiry backoff silent memory replay restart chaos),
        else: names

    IO.puts("jobq bench: #{Enum.join(names, ", ")}  (#{jobs} jobs where it matters)")
    IO.puts(String.duplicate("-", 64))
    Enum.each(names, &run(&1, jobs))
  end

  defp run("throughput", jobs) do
    for workers <- [1, 32] do
      %{port: port, stop: stop} = service()
      {microseconds, :ok} = :timer.tc(fn -> fill(port, jobs) end)
      report("create, 8 connections", jobs, microseconds)

      {microseconds, acked} =
        :timer.tc(fn ->
          1..workers
          |> Task.async_stream(fn _n -> work(Conn.open(port), 0) end,
            max_concurrency: workers,
            timeout: :infinity
          )
          |> Enum.reduce(0, fn {:ok, count}, total -> total + count end)
        end)

      report("lease+ack, #{workers} worker(s)", acked, microseconds)
      stop.()
    end
  end

  defp run("expiry", _jobs) do
    %{port: port, stop: stop} = service()
    worker = Conn.open(port)
    {201, _job} = Conn.request(worker, "alice", "POST", "/jobs", job_body(1, 100))
    {200, leased} = Conn.request(worker, "bob", "POST", "/queues/#{@queue}/lease", ~s({"lease_ms":200}))
    until = leased |> JSON.decode!() |> Map.fetch!("lease_until") |> to_unix_ms()

    # A steady stream of lease requests on the queue, which is what the spec
    # asks the lag to be measured under.
    handed_out = poll_until_leased(worker, until)
    IO.puts(pad("lease expiry to hand-out") <> "#{handed_out - until} ms")
    stop.()
  end

  # The same lag for the other deadline the change adds: a `run_at` that has
  # passed, on a job put back with a backoff.
  defp run("backoff", _jobs) do
    %{port: port, stop: stop} = service()
    worker = Conn.open(port)

    {201, _job} =
      Conn.request(worker, "alice", "POST", "/jobs", job_body(1, 100, backoff_ms: 200))

    {200, _leased} =
      Conn.request(worker, "bob", "POST", "/queues/#{@queue}/lease", ~s({"lease_ms":60000}))

    {200, failed} = Conn.request(worker, "bob", "POST", "/jobs/j_1/fail")
    %{"state" => "scheduled", "run_at" => run_at} = JSON.decode!(failed)
    until = to_unix_ms(run_at)

    handed_out = poll_until_leased(worker, until)
    IO.puts(pad("backoff run_at to hand-out") <> "#{handed_out - until} ms")
    stop.()
  end

  defp run("silent", _jobs) do
    %{port: port, stop: stop} = service()
    before = :erlang.memory(:total)

    silent =
      for _n <- 1..1_200 do
        {:ok, socket} =
          :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)

        socket
      end

    Process.sleep(300)
    held = :erlang.memory(:total) - before

    producer = Conn.open(port)

    times =
      for n <- 1..20 do
        {microseconds, {201, _job}} =
          :timer.tc(fn -> Conn.request(producer, "alice", "POST", "/jobs", job_body(n, 1)) end)

        microseconds
      end
      |> Enum.sort()

    IO.puts(pad("1,200 silent connections") <> "#{mib(held)} MiB on the node")

    IO.puts(
      pad("a create while they hold") <>
        "#{ms(Enum.at(times, 10))} ms median, #{ms(List.first(times))} best, #{ms(List.last(times))} worst, of 20"
    )
    Enum.each(silent, &:gen_tcp.close/1)
    stop.()
  end

  defp run("memory", _jobs) do
    %{port: port, stop: stop, pid: queue} = service()
    fill(port, 100_000)
    :erlang.garbage_collect(queue)
    Process.sleep(200)

    IO.puts(pad("resident memory at 100k jobs") <> "#{rss_mb()} MiB (the node, bench included)")
    IO.puts(pad("BEAM total at 100k jobs") <> "#{mib(:erlang.memory(:total))} MiB")
    IO.puts(pad("the queue process at 100k jobs") <> "#{mib(process_bytes(queue))} MiB")
    stop.()
  end

  defp run("replay", _jobs) do
    dir = tmp_dir()
    records = 1_000_000

    lines =
      Stream.map(1..records, fn n ->
        [
          Jobq.Json.encode(
            Jobq.Job.record(%Jobq.Job{
              n: n,
              queue: @queue,
              payload: "a payload of the usual size, about sixty bytes of it.",
              max_tries: 3,
              tries: rem(n, 3),
              state: :queued,
              created_at: 1_789_000_000_000,
              updated_at: 1_789_000_000_000
            })
          ),
          ?\n
        ]
      end)

    File.open!(Jobq.Store.log_path(dir), [:write, :raw, :binary], fn fd ->
      Enum.each(Stream.chunk_every(lines, 10_000), &:file.write(fd, &1))
    end)

    size = File.stat!(Jobq.Store.log_path(dir)).size
    {microseconds, {:ok, {jobs, _next}}} = :timer.tc(fn -> Jobq.Store.read(dir) end)
    IO.puts(pad("replay of #{records} records") <> "#{ms(microseconds)} ms, #{div(size, 1_048_576)} MiB, #{map_size(jobs)} jobs")

    {microseconds, %{stop: stop}} = :timer.tc(fn -> service(dir) end)
    IO.puts(pad("start on that store") <> "#{ms(microseconds)} ms")
    stop.()
    File.rm_rf(dir)
  end

  defp run("restart", _jobs) do
    dir = tmp_dir()
    %{port: port, stop: stop} = service(dir)
    fill(port, 10_000)
    connection = Conn.open(port)
    Enum.each(1..10_000, fn _n ->
      {200, _job} = Conn.request(connection, "bob", "POST", "/queues/#{@queue}/lease", ~s({"lease_ms":3600000}))
    end)

    stop.()
    {microseconds, %{stop: stop}} = :timer.tc(fn -> service(dir) end)
    IO.puts(pad("start with 10,000 leased jobs") <> "#{ms(microseconds)} ms")
    stop.()
    File.rm_rf(dir)
  end

  # The chaos switch under the create load: every 500th write fails the board,
  # and a client told 503 creates again. Every answer is 201 or 503, every 201 is on the log afterwards, and the
  # longest the service answered /health with anything but 200 is the time a
  # restart takes on a log of the size the load has made.
  defp run("chaos", jobs) do
    dir = tmp_dir()
    %{port: port, stop: stop, ref: ref} = service(dir, crash_every: 500, max_restarts: 1_000_000)
    watcher = Task.async(fn -> watch_health(port, nil, 0) end)

    {microseconds, answers} =
      :timer.tc(fn ->
        1..jobs
        |> Enum.chunk_every(div(jobs, 8) + 1)
        |> Task.async_stream(
          fn chunk ->
            connection = Conn.open(port)

            Enum.flat_map(chunk, &create_until_served(connection, &1, []))
          end,
          max_concurrency: 8,
          timeout: :infinity
        )
        |> Enum.flat_map(fn {:ok, answers} -> answers end)
      end)

    send(watcher.pid, :stop)
    longest = Task.await(watcher, :infinity)
    health = settled_health(ref)
    restarts = health |> Jobq.Json.encode() |> JSON.decode!() |> Map.fetch!("restarts")
    stop.()

    {:ok, {log, _next}} = Jobq.Store.read(dir)
    ids = MapSet.new(Map.values(log), &Jobq.Job.id/1)
    created = for {201, id} <- answers, do: id
    refused = Enum.count(answers, &match?({503, _id}, &1))
    missing = Enum.count(created, &(not MapSet.member?(ids, &1)))

    report("create under --crash-every 500", jobs, microseconds)
    IO.puts(pad("answers") <> "#{length(created)} x 201, #{refused} x 503, #{restarts} restarts")
    IO.puts(pad("201s missing from the log") <> "#{missing}")
    IO.puts(pad("longest /health gap") <> "#{longest} ms, on a log of up to #{map_size(log)} jobs")
    File.rm_rf(dir)
  end

  defp run(name, _jobs), do: IO.puts("bench: no such measurement: #{name}")

  # A client that is told 503 waits a moment and creates again, as a real one
  # would; the job the 503 was for may be on the log as well, which is the
  # spec's word on a 503 the failure caused.
  defp create_until_served(connection, n, answers) do
    case Conn.request(connection, "alice", "POST", "/jobs", job_body(n, 3)) do
      {201, body} ->
        [{201, body |> JSON.decode!() |> Map.fetch!("id")} | answers]

      {503, _body} ->
        Process.sleep(5)
        create_until_served(connection, n, [{503, nil} | answers])
    end
  end

  defp settled_health(ref) do
    case Jobq.Queue.health(ref) do
      {200, health} -> health
      _restarting -> Process.sleep(5) && settled_health(ref)
    end
  end

  # The longest stretch, in ms, over which /health was not 200.
  defp watch_health(port, down_since, longest) do
    receive do
      :stop -> longest
    after
      2 ->
        now = System.monotonic_time(:millisecond)

        case {Jobq.Client.request({127, 0, 0, 1}, port, "", "GET", "/health", nil), down_since} do
          {{:ok, 200, _body}, nil} -> watch_health(port, nil, longest)
          {{:ok, 200, _body}, since} -> watch_health(port, nil, max(longest, now - since))
          {_down, nil} -> watch_health(port, now, longest)
          {_down, since} -> watch_health(port, since, longest)
        end
    end
  end

  # The service, and the two ways of talking to it.

  defp service(dir \\ nil, opts \\ []) do
    dir = dir || tmp_dir()
    ref = make_ref()
    {:ok, pid} = Jobq.Server.start_link([ref: ref, dir: dir, port: 0] ++ opts)

    %{
      ref: ref,
      pid: Jobq.Registry.whereis(ref, :queue),
      port: Jobq.Server.port(ref),
      dir: dir,
      stop: fn -> Supervisor.stop(pid) end
    }
  end

  defp fill(port, count) do
    connections = for _n <- 1..8, do: Conn.open(port)

    1..count
    |> Enum.chunk_every(div(count, 8) + 1)
    |> Enum.zip(connections)
    |> Task.async_stream(
      fn {chunk, connection} ->
        Enum.each(chunk, fn n ->
          {201, _job} = Conn.request(connection, "alice", "POST", "/jobs", job_body(n, 3))
        end)
      end,
      max_concurrency: 8,
      timeout: :infinity
    )
    |> Stream.run()
  end

  defp work(connection, count) do
    case Conn.request(connection, "bob", "POST", "/queues/#{@queue}/lease", ~s({"lease_ms":60000})) do
      {204, _body} ->
        count

      {200, body} ->
        id = body |> JSON.decode!() |> Map.fetch!("id")
        {200, _acked} = Conn.request(connection, "bob", "POST", "/jobs/#{id}/ack")
        work(connection, count + 1)
    end
  end

  defp poll_until_leased(connection, until) do
    case Conn.request(connection, "eve", "POST", "/queues/#{@queue}/lease", ~s({"lease_ms":1000})) do
      {200, _job} -> System.system_time(:millisecond)
      {204, _body} -> poll_until_leased(connection, until)
    end
  end

  defp job_body(n, max_tries, opts \\ []) do
    %{
      "queue" => @queue,
      "payload" => "payload number #{n}, about sixty bytes of it all told.",
      "max_tries" => max_tries
    }
    |> Map.merge(Map.new(opts, fn {key, value} -> {Atom.to_string(key), value} end))
    |> JSON.encode!()
  end

  defp to_unix_ms(iso) do
    {:ok, datetime, 0} = DateTime.from_iso8601(iso)
    DateTime.to_unix(datetime, :millisecond)
  end

  defp process_bytes(pid) do
    {:memory, bytes} = Process.info(pid, :memory)
    bytes
  end

  defp rss_mb do
    "/proc/self/status"
    |> File.read!()
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case String.split(line) do
        ["VmRSS:", kilobytes, _unit] -> div(String.to_integer(kilobytes), 1024)
        _other -> nil
      end
    end)
  end

  defp report(name, count, microseconds) do
    per_second = round(count * 1_000_000 / microseconds)
    IO.puts(pad(name) <> "#{per_second}/s  (#{count} in #{ms(microseconds)} ms)")
  end

  defp ms(microseconds), do: Float.round(microseconds / 1_000, 1)
  defp mib(bytes), do: Float.round(bytes / 1_048_576, 1)
  defp pad(name), do: String.pad_trailing(name <> "  ", 34, ".") <> "  "

  defp tmp_dir do
    # The node's unique integers start over in every VM, so the name carries
    # the OS pid too: two `mix run` invocations must not land on one directory.
    name = "jobq-bench-#{System.pid()}-#{System.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), name)
    File.mkdir_p!(dir)
    dir
  end
end

Bench.main(System.argv())
