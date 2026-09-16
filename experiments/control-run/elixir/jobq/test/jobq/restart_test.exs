defmodule Jobq.RestartTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Jobq.Job
  alias Jobq.Json
  alias Jobq.Queue
  alias Jobq.Store
  alias Jobq.Test.Api
  alias Jobq.Test.Clock
  alias Jobq.Test.Never
  alias Jobq.Test.Service

  # Every test here fails the board on purpose, and the crash reports that
  # follow are the point rather than news.
  @moduletag capture_log: true

  describe "the store restarts itself" do
    test "the chaos switch fails the N-th write after it is on the disk, and the board comes back as the log holds it" do
      %{ref: ref, dir: dir} = Service.start(crash_every: 3)

      assert {201, _job} = Queue.create(ref, "emails", "one", 3)
      assert {201, _job} = Queue.create(ref, "emails", "two", 3)
      assert {200, %{"restarts" => 0}} = health(ref)

      # The third write is on the disk and its response is never sent.
      assert {:error, :store} = Queue.create(ref, "emails", "three", 3)
      assert {200, %{"restarts" => 1, "queued" => 3}} = wait_health(ref)
      assert board(ref) == log(dir)
      assert {200, %{"payload" => "three"}} = get(ref, "j_3")

      # Ids go on from the log, and the next two writes are served.
      assert {201, %{"id" => "j_4"}} = Queue.create(ref, "emails", "four", 3) |> decoded()
      assert {200, %{"id" => "j_1"}} = Queue.lease(ref, "emails", 60_000, "bob") |> decoded()
      assert {:error, :store} = Queue.ack(ref, "j_1", "bob")
      assert {200, %{"restarts" => 2, "done" => 1}} = wait_health(ref)
      assert board(ref) == log(dir)
      assert :ok = Never.check(dir)
    end

    test "the queue killed: the board is rebuilt, the port stays bound, and the next client is served" do
      %{ref: ref, dir: dir, port: port} = Service.start()

      assert {201, _job} = Queue.create(ref, "emails", "one", 3)
      assert {200, _job} = Queue.lease(ref, "emails", 60_000, "bob")
      {200, leased} = get(ref, "j_1")

      kill(ref, :queue)

      assert {200, %{"restarts" => 1, "leased" => 1}} = wait_health(ref)
      assert Jobq.Server.port(ref) == port
      assert {200, ^leased} = Api.request(port, "alice", "GET", "/jobs/j_1")
      assert board(ref) == log(dir)

      # The lease is held with its lease_until, and only its holder acks it.
      assert {409, _error} = Api.request(port, "eve", "POST", "/jobs/j_1/ack")
      assert {200, %{"state" => "done"}} = Api.request(port, "bob", "POST", "/jobs/j_1/ack")
    end

    test "the store killed: both are started again and nothing written is lost" do
      %{ref: ref, dir: dir} = Service.start()

      for n <- 1..20, do: {201, _job} = Queue.create(ref, "emails", "job #{n}", 3)
      kill(ref, :store)

      assert {200, %{"restarts" => 1, "queued" => 20}} = wait_health(ref)
      assert board(ref) == log(dir)
      assert {201, %{"id" => "j_21"}} = Queue.create(ref, "emails", "more", 3) |> decoded()
    end

    test "a look that breaks a rule inside the service is the board's failure, not a request's" do
      %{ref: ref, dir: dir, clock: clock} = Service.start()

      assert {201, _job} = Queue.create(ref, "emails", "one", 3)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")

      # The index says a lease runs out that the jobs no longer have.
      pid = Jobq.Registry.whereis(ref, :queue)
      :sys.replace_state(pid, fn state -> %{state | jobs: %{}} end)
      Clock.advance(clock, 1_001)

      assert {:error, :store} = Queue.get(ref, "j_1")
      assert {200, %{"restarts" => 1}} = wait_health(ref)
      assert board(ref) == log(dir)
      assert {200, %{"state" => "queued", "tries" => 1}} = get(ref, "j_1")
    end

    test "a request while the board is down is 503, and the one after it is served" do
      %{ref: ref, port: port} = Service.start()
      board = Jobq.Registry.whereis(ref, :board)

      :ok = Supervisor.terminate_child(board, Jobq.Queue)
      assert {503, %{"error" => _message}} = Api.request(port, "", "GET", "/health")
      assert {503, _error} = Api.request(port, "alice", "GET", "/jobs")

      {:ok, _pid} = Supervisor.restart_child(board, Jobq.Queue)
      assert {200, _health} = Api.request(port, "", "GET", "/health")
    end

    test "the uptime is the service's and is not started again by a restart" do
      %{ref: ref, clock: clock} = Service.start()
      Clock.advance(clock, 5_000)
      kill(ref, :queue)
      assert {200, %{"uptime_ms" => 5_000, "restarts" => 1}} = wait_health(ref)
    end

    test "on a log of 100,000 records /health is 200 within a second of the failure" do
      dir = Service.tmp_dir()
      write_log(dir, 100_000)
      %{ref: ref} = Service.start(dir: dir)

      failed = System.monotonic_time(:millisecond)
      kill(ref, :store)
      assert {200, %{"restarts" => 1, "queued" => 100_000}} = wait_health(ref)
      assert System.monotonic_time(:millisecond) - failed < 1_000
    end

    test "a torn final line a killed service left is cut, and the next record starts a line" do
      dir = Service.tmp_dir()
      write_log(dir, 1)
      File.write!(Store.log_path(dir), ~s({"id":"j_2","queue":"ema), [:append])

      {%{ref: ref}, warning} = with_log(fn -> Service.start(dir: dir) end)
      assert warning =~ "cutting a torn final line"
      assert {201, %{"id" => "j_2"}} = Queue.create(ref, "emails", "two", 1) |> decoded()
      assert {:ok, {jobs, 3}} = Store.read(dir)
      assert map_size(jobs) == 2
    end
  end

  describe "the budget" do
    test "one failure more than the budget inside the window stops the service, and the log opens" do
      Process.flag(:trap_exit, true)
      %{ref: ref, dir: dir, pid: pid} = Service.start(crash_every: 1, max_restarts: 2)

      # Every write fails: the first two failures are restarts, the third stops.
      for n <- 1..3 do
        assert {:error, :store} = Queue.create(ref, "emails", "job #{n}", 1)
        if n < 3, do: assert({200, %{"restarts" => ^n}} = wait_health(ref))
      end

      assert_receive {:EXIT, ^pid, :shutdown}, 5_000
      assert {:ok, {jobs, 4}} = Store.read(dir)
      assert map_size(jobs) == 3

      # The folder serves again, from 0 restarts.
      %{ref: ref} = Service.start(dir: dir)
      assert {200, %{"restarts" => 0, "queued" => 3}} = health(ref)
    end

    test "a failure after the window has passed starts a fresh count" do
      Process.flag(:trap_exit, true)

      %{ref: ref, pid: pid} =
        Service.start(crash_every: 1, max_restarts: 1, restart_window: 1)

      assert {:error, :store} = Queue.create(ref, "emails", "one", 1)
      assert {200, %{"restarts" => 1}} = wait_health(ref)
      Process.sleep(2_100)

      assert {:error, :store} = Queue.create(ref, "emails", "two", 1)
      assert {200, %{"restarts" => 2}} = wait_health(ref)
      refute_received {:EXIT, ^pid, _reason}

      # Inside the window again: this one is over the budget.
      assert {:error, :store} = Queue.create(ref, "emails", "three", 1)
      assert_receive {:EXIT, ^pid, :shutdown}, 5_000
    end
  end

  describe "under failures at random writes" do
    test "every answer is right or a failure, and every write a 2xx reported is on the board after" do
      :rand.seed(:exsss, {1, 2, 3})
      crash = fn _write -> :rand.uniform(15) == 1 end

      %{ref: ref, dir: dir, pid: pid, clock: clock} =
        Service.start(crash: crash, max_restarts: 1_000)

      # What a 2xx said each job was, by id, in the order the answers came.
      acknowledged =
        Enum.reduce(1..150, %{}, fn round, seen ->
          seen
          |> note(settled(ref, fn -> Queue.create(ref, "emails", "p#{round}", 2) end))
          |> note(settled(ref, fn -> Queue.lease(ref, "emails", 60_000, "bob") end))
          |> finish(ref, round)
        end)

      assert map_size(acknowledged) > 100
      assert {200, %{"restarts" => restarts}} = wait_health(ref)
      assert restarts > 5
      assert :ok = Never.check(dir)

      board = board(ref)
      assert board == log(dir)
      assert_present(acknowledged, board)

      Service.stop(pid)
      %{ref: ref} = Service.start(dir: dir, clock: clock)
      assert board(ref) == board
    end
  end

  describe "the chaos switch under load over the wire" do
    test "every response is 2xx, 4xx, or 503 (or a closed connection), and every 2xx job is there after" do
      %{ref: ref, dir: dir, port: port} = Service.start(crash_every: 25, max_restarts: 1_000)

      results =
        1..16
        |> Task.async_stream(
          fn worker -> Enum.flat_map(1..40, fn n -> traffic(port, worker, n) end) end,
          max_concurrency: 16,
          timeout: 60_000
        )
        |> Enum.flat_map(fn {:ok, answers} -> answers end)

      statuses = results |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
      assert Enum.all?(statuses, &(&1 in [200, 201, 204, 409, 503, :closed])), inspect(statuses)
      assert 503 in statuses or :closed in statuses

      created = for {201, %{"id" => id}} <- results, do: id
      assert length(created) > 100

      assert {200, %{"restarts" => restarts}} = wait_health(ref)
      assert restarts >= 1
      board = board(ref)
      assert Enum.all?(created, &Map.has_key?(board, &1))
      assert board == log(dir)
      assert :ok = Never.check(dir)
    end
  end

  # One worker's step: a create, a lease, and an ack of what it leased, with
  # every answer kept.
  defp traffic(port, worker, n) do
    token = "w#{worker}"
    body = ~s({"queue":"load","payload":"#{worker}-#{n}","max_tries":3})
    created = request(port, token, "POST", "/jobs", body)
    leased = request(port, token, "POST", "/queues/load/lease")

    case leased do
      {200, %{"id" => id}} -> [created, leased, request(port, token, "POST", "/jobs/#{id}/ack")]
      _other -> [created, leased]
    end
  end

  defp request(port, token, method, path, body \\ nil) do
    case Jobq.Client.request({127, 0, 0, 1}, port, token, method, path, body) do
      {:ok, status, ""} -> {status, nil}
      {:ok, status, text} -> {status, JSON.decode!(text)}
      {:error, _reason} -> {:closed, nil}
    end
  end

  # A request, and if the failure hit it, the wait for the board to be back.
  defp settled(ref, request) do
    case request.() do
      {:error, :store} ->
        {200, _health} = wait_health(ref)
        :failed

      {status, body} ->
        {status, body && JSON.decode!(Json.encode(body))}
    end
  end

  defp note(seen, {status, %{"id" => id} = job}) when status in 200..299,
    do: Map.put(seen, id, job)

  defp note(seen, _answer), do: seen

  defp finish(seen, ref, round) do
    case Map.values(seen) |> Enum.filter(&(&1["state"] == "leased" and &1["worker"] == "bob")) do
      [] ->
        seen

      [job | _rest] ->
        note_or_read(seen, ref, job["id"], settle_lease(ref, job["id"], round))
    end
  end

  # Every fourth round fails its lease; the others ack it.
  defp settle_lease(ref, id, round) when rem(round, 4) == 0,
    do: settled(ref, fn -> Queue.fail(ref, id, "bob", "boom") end)

  defp settle_lease(ref, id, _round), do: settled(ref, fn -> Queue.ack(ref, id, "bob") end)

  # A failed answer leaves the job unknown to the client, so it reads it.
  defp note_or_read(seen, _ref, _id, {status, _body} = reply) when status in 200..299,
    do: note(seen, reply)

  defp note_or_read(seen, ref, id, _answer),
    do: note(seen, settled(ref, fn -> Queue.get(ref, id) end))

  # What a 2xx reported is there, in that state or one it has moved on to
  # since; a lease that was reported stays held until the test lets it go.
  defp assert_present(acknowledged, board) do
    Enum.each(acknowledged, fn {id, job} ->
      assert %{"state" => state} = Map.fetch!(board, id)

      case job["state"] do
        "done" -> assert state == "done"
        "dead" -> assert state == "dead"
        "leased" -> assert state in ["leased", "done", "dead", "queued"]
        "queued" -> assert state in ["queued", "leased", "done", "dead"]
      end
    end)
  end

  # The board as a client reads it, by id.
  defp board(ref) do
    pid = Jobq.Registry.whereis(ref, :queue)
    %{jobs: jobs} = :sys.get_state(pid)
    Map.new(jobs, fn {_n, job} -> {Job.id(job), rendered(job)} end)
  end

  # The board the log holds, as the same client would read it.
  defp log(dir) do
    {:ok, {jobs, _next}} = Store.read(dir)
    Map.new(jobs, fn {_n, job} -> {Job.id(job), rendered(job)} end)
  end

  defp rendered(job), do: job |> Job.render() |> Json.encode() |> JSON.decode!()

  defp health(ref), do: Queue.health(ref) |> decoded()
  defp get(ref, id), do: Queue.get(ref, id) |> decoded()

  defp decoded({status, nil}), do: {status, nil}
  defp decoded({status, body}), do: {status, body |> Json.encode() |> JSON.decode!()}
  defp decoded(other), do: other

  # /health, as soon as the board answers it, within five seconds.
  defp wait_health(ref, tries \\ 500) do
    case health(ref) do
      {200, _body} = answer ->
        answer

      _other when tries > 0 ->
        Process.sleep(10)
        wait_health(ref, tries - 1)
    end
  end

  # A process of the board killed, and the queue it was serving gone with it:
  # what answers next is the board that was rebuilt, or nothing.
  defp kill(ref, role) do
    queue = Jobq.Registry.whereis(ref, :queue)
    watch = Process.monitor(queue)
    pid = Jobq.Registry.whereis(ref, role)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^watch, :process, ^queue, _reason}
  end

  defp write_log(dir, count) do
    lines =
      for n <- 1..count do
        job = %Job{
          n: n,
          queue: "emails",
          payload: "job #{n}",
          max_tries: 3,
          backoff_ms: 0,
          tries: 0,
          state: :queued,
          created_at: 1_789_000_000_000,
          updated_at: 1_789_000_000_000
        }

        [Json.encode(Job.record(job)), ?\n]
      end

    File.write!(Store.log_path(dir), lines)
  end
end
