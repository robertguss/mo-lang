defmodule Jobq.ArchiveTest do
  @moduledoc """
  Change 4: idempotent creates, and old jobs archived out of the log.
  """

  use ExUnit.Case, async: true

  alias Jobq.Archive
  alias Jobq.Job
  alias Jobq.Json
  alias Jobq.Queue
  alias Jobq.Store
  alias Jobq.Test.Api
  alias Jobq.Test.Clock
  alias Jobq.Test.Never
  alias Jobq.Test.Service

  @retain 60_000

  @moduletag capture_log: true

  describe "the move, as a pure step" do
    test "a done or dead job is due once its updated_at is retain_ms before now" do
      done = job(1, state: :done, tries: 1, updated_at: 1_000)

      refute Archive.due?(done, 1_000 + @retain - 1, @retain)
      assert Archive.due?(done, 1_000 + @retain, @retain)
      assert Archive.due?(%{done | state: :dead}, 1_000 + @retain, @retain)
      refute Archive.due?(%{done | state: :queued, tries: 0}, 10 * @retain, @retain)
      refute Archive.due?(%{done | state: :scheduled, tries: 0}, 10 * @retain, @retain)
      refute Archive.due?(%{done | state: :leased}, 10 * @retain, @retain)
    end

    test "writes the archive's record first and the log's word second" do
      done = job(4, state: :done, tries: 1, key: "k")

      assert {archived, [{:archive, written}, {:archived, "j_4"}]} = Archive.move(done, 99)
      assert written == archived
      assert archived == %{done | archived_at: 99}
      assert_raise FunctionClauseError, fn -> Archive.move(%{done | state: :queued}, 99) end
    end
  end

  describe "the key" do
    test "a second create with the key answers the first job in every state, and a delete frees it" do
      %{ref: ref, clock: clock} = start([])
      again = fn -> create(ref, "emails", "k", payload: "ignored", max_tries: 9, delay_ms: 5) end

      assert {201, %{"id" => "j_1", "state" => "scheduled", "key" => "k"}} =
               create(ref, "emails", "k", delay_ms: 1_000)

      assert {200, %{"id" => "j_1", "state" => "scheduled", "payload" => "p"}} = again.()
      Clock.advance(clock, 1_000)
      assert {200, %{"id" => "j_1", "state" => "queued", "max_tries" => 2}} = again.()
      assert {200, _leased} = decoded(Queue.lease(ref, "emails", 1_000, "bob"))
      assert {200, %{"id" => "j_1", "state" => "leased"}} = again.()
      assert {200, _dead} = decoded(Queue.fail(ref, "j_1", "bob", "no"))
      assert {200, %{"id" => "j_1", "state" => "queued", "tries" => 1}} = again.()
      assert {200, _leased} = decoded(Queue.lease(ref, "emails", 1_000, "bob"))
      assert {200, _dead} = decoded(Queue.fail(ref, "j_1", "bob", "no"))
      assert {200, %{"id" => "j_1", "state" => "dead"}} = again.()
      assert {200, _queued} = decoded(Queue.retry(ref, "j_1"))
      assert {200, _leased} = decoded(Queue.lease(ref, "emails", 1_000, "bob"))
      assert {200, _done} = decoded(Queue.ack(ref, "j_1", "bob"))
      assert {200, %{"id" => "j_1", "state" => "done"}} = again.()

      Clock.advance(clock, @retain)
      assert {200, %{"id" => "j_1", "state" => "done", "archived_at" => _at}} = again.()
      assert {200, %{"archived" => 1}} = decoded(Queue.health(ref))

      # Nothing any of those made: one job, ever.
      assert {201, %{"id" => "j_2"}} = create(ref, "emails", nil)
      assert {204, nil} = Queue.delete(ref, "j_1")
      assert {201, %{"id" => "j_3", "key" => "k"}} = again.()
      assert {200, %{"id" => "j_3"}} = again.()
      assert {204, nil} = Queue.delete(ref, "j_3")
      assert {201, %{"id" => "j_4"}} = again.()
    end

    test "the same key in another queue is another job, and a listing finds it by queue" do
      %{ref: ref, port: port} = Service.start()

      assert {201, %{"id" => "j_1"}} = create(ref, "emails", "k")
      assert {201, %{"id" => "j_2"}} = create(ref, "reports", "k")
      assert {201, %{"id" => "j_3"}} = create(ref, "emails", "other")

      assert {200, %{"jobs" => [%{"id" => "j_2"}]}} =
               Api.request(port, "alice", "GET", "/jobs?queue=reports&key=k")

      assert {200, %{"jobs" => []}} =
               Api.request(port, "alice", "GET", "/jobs?queue=reports&key=k&state=done")

      assert {200, %{"jobs" => []}} = Api.request(port, "alice", "GET", "/jobs?queue=q&key=k")

      assert {400, %{"error" => "key needs a queue"}} =
               Api.request(port, "alice", "GET", "/jobs?key=k")

      assert {400, %{"error" => "key must be 1 to 64 bytes"}} =
               Api.request(port, "alice", "GET", "/jobs?queue=emails&key=")

      body = ~s({"queue":"emails","payload":"x","max_tries":1,"key":7})

      assert {400, %{"error" => "key must be a string"}} =
               Api.request(port, "alice", "POST", "/jobs", body)

      body = ~s({"queue":"emails","payload":"x","max_tries":1,"key":"k"})
      assert {200, %{"id" => "j_1"}} = Api.request(port, "alice", "POST", "/jobs", body)
    end

    test "the map is rebuilt from a log the test wrote, and survives a restart and a compaction" do
      dir = Service.tmp_dir()

      write(Store.log_path(dir), [
        job(1, key: "a") |> Job.record(),
        job(2, key: "b", state: :done, tries: 1) |> Job.record(),
        job(3, key: "c") |> Job.record(),
        {:obj, [{"id", "j_3"}, {"deleted", true}]}
      ])

      write(Store.archive_path(dir), [
        job(4, key: "d", state: :dead, tries: 1, archived_at: 5) |> Job.record()
      ])

      %{ref: ref, pid: pid, clock: clock} = Service.start(dir: dir)
      assert_keys(ref)

      # Change 3's restart.
      kill(ref, :queue)
      wait_health(ref)
      assert_keys(ref)

      # A stop, a compaction, and a start.
      Service.stop(pid)
      assert {:ok, 2} = Store.compact(dir)
      %{ref: ref} = Service.start(dir: dir, clock: clock)
      assert_keys(ref)
      # Each look at the keys made one job and deleted it: j_5, j_6 and j_7.
      assert {201, %{"id" => "j_8", "key" => "c"}} = create(ref, "emails", "c")
    end

    test "a folder where a key names two jobs of a queue is refused" do
      dir = Service.tmp_dir()
      write(Store.log_path(dir), [job(1, key: "a") |> Job.record()])
      write(Store.archive_path(dir), [job(2, key: "a", state: :done, tries: 1, archived_at: 1)])

      assert {:error, {:record, "j_2", "the key names another job in its queue"}} =
               Store.open(dir)
    end
  end

  describe "the archive" do
    test "a done or dead job past retain_ms leaves the board, with both writes on the disk first" do
      %{ref: ref, dir: dir, clock: clock} = start([])

      assert {201, _job} = create(ref, "emails", "k")
      assert {201, _job} = create(ref, "emails", nil, max_tries: 1)
      assert {201, _job} = create(ref, "emails", nil)
      assert {200, _job} = decoded(Queue.lease(ref, "emails", 1_000, "bob"))
      assert {200, _job} = decoded(Queue.ack(ref, "j_1", "bob"))
      assert {200, _job} = decoded(Queue.lease(ref, "emails", 1_000, "bob"))
      assert {200, _job} = decoded(Queue.fail(ref, "j_2", "bob", "no"))

      Clock.advance(clock, @retain - 1)
      assert {200, %{"done" => 1, "dead" => 1, "archived" => 0}} = decoded(Queue.health(ref))
      assert File.read!(Store.archive_path(dir)) == ""

      Clock.advance(clock, 1)
      now = Clock.now(clock)
      assert {200, health} = decoded(Queue.health(ref))
      assert %{"queued" => 1, "done" => 0, "dead" => 0, "archived" => 2} = health

      # The answer came after both files had the move.
      assert [one, two] = lines(Store.archive_path(dir))
      assert %{"id" => "j_1", "state" => "done", "key" => "k", "archived_at" => ^now} = one
      assert %{"id" => "j_2", "state" => "dead", "reason" => "no", "archived_at" => ^now} = two

      assert [%{"id" => "j_1", "archived" => true}, %{"id" => "j_2", "archived" => true}] =
               lines(Store.log_path(dir)) |> Enum.filter(& &1["archived"])

      assert {200, %{"archived_at" => _at, "state" => "done"}} = decoded(Queue.get(ref, "j_1"))
      assert {200, %{"jobs" => [%{"id" => "j_3"}]}} = decoded(Queue.list(ref, nil, nil))
      assert {200, %{"jobs" => []}} = decoded(Queue.list(ref, "emails", nil, "k"))

      assert {200, %{"queues" => [%{"name" => "emails", "queued" => 1}]}} =
               decoded(Queue.queues(ref))

      assert {409, %{"error" => "archived"}} = decoded(Queue.retry(ref, "j_2"))
      assert {409, _error} = decoded(Queue.ack(ref, "j_1", "bob"))
      assert :ok = Never.check(dir)

      # A delete is a tombstone in the archive until the next compaction.
      assert {204, nil} = Queue.delete(ref, "j_2")
      assert {404, _error} = decoded(Queue.get(ref, "j_2"))
      assert {200, %{"archived" => 1}} = decoded(Queue.health(ref))
      assert %{"id" => "j_2", "deleted" => true} = List.last(lines(Store.archive_path(dir)))
    end

    test "an archived job survives a restart and a compaction, and never comes back to the board" do
      %{ref: ref, dir: dir, pid: pid, clock: clock} = start([])

      assert {201, _job} = create(ref, "emails", "k")
      assert {201, _job} = create(ref, "emails", nil)
      assert {200, _job} = decoded(Queue.lease(ref, "emails", 1_000, "bob"))
      assert {200, _job} = decoded(Queue.ack(ref, "j_1", "bob"))
      assert {200, _job} = decoded(Queue.lease(ref, "emails", 1_000, "bob"))
      assert {200, _job} = decoded(Queue.ack(ref, "j_2", "bob"))
      Clock.advance(clock, @retain)
      assert {200, %{"archived" => 2}} = decoded(Queue.health(ref))
      assert {204, nil} = Queue.delete(ref, "j_2")

      kill(ref, :store)
      assert {200, %{"archived" => 1, "done" => 0}} = wait_health(ref)

      Service.stop(pid)
      assert {:ok, 0} = Store.compact(dir)
      assert lines(Store.log_path(dir)) == [%{"next" => 3}]
      assert [%{"id" => "j_1", "archived_at" => _at}] = lines(Store.archive_path(dir))

      %{ref: ref} = start(dir: dir, clock: clock)
      assert {200, %{"archived" => 1, "done" => 0}} = decoded(Queue.health(ref))
      assert {200, %{"id" => "j_1", "archived_at" => _at}} = decoded(Queue.get(ref, "j_1"))
      assert {404, _error} = decoded(Queue.get(ref, "j_2"))
      assert {200, %{"id" => "j_1"}} = create(ref, "emails", "k")
      assert {201, %{"id" => "j_3"}} = create(ref, "emails", nil)
      assert {204, nil} = Queue.delete(ref, "j_1")
      assert {:ok, %{archived: archived}} = Store.open(dir)
      assert archived == %{}
    end

    test "a job in both files opens archived, counted once" do
      dir = Service.tmp_dir()
      done = job(1, state: :done, tries: 1, key: "k")

      # The kill fell between the archive's append and the log's record.
      write(Store.log_path(dir), [Job.record(done), Job.record(job(2))])
      write(Store.archive_path(dir), [Job.record(%{done | archived_at: 7})])

      assert {:ok, %{jobs: jobs, archived: archived, next: 3}} = Store.open(dir)
      assert Map.keys(jobs) == [2]
      assert Map.keys(archived) == [1]

      %{ref: ref} = Service.start(dir: dir)
      assert {200, %{"queued" => 1, "done" => 0, "archived" => 1}} = decoded(Queue.health(ref))
      assert {200, %{"id" => "j_1", "archived_at" => _at}} = create(ref, "emails", "k")

      # And deleted from the archive, it does not come back from the log.
      assert {204, nil} = Queue.delete(ref, "j_1")
      assert {:ok, %{jobs: jobs, archived: %{}}} = Store.open(dir)
      assert Map.keys(jobs) == [2]
    end

    test "the move's two writes cut apart by a failing batch: archived once, never live again" do
      # One batch fails, as the test arms it: 1 between the writes, 2 before.
      armed = :counters.new(1, [])

      fault = fn _batch ->
        case :counters.get(armed, 1) do
          0 ->
            false

          mode ->
            :counters.put(armed, 1, 0)
            if mode == 1, do: :between, else: true
        end
      end

      %{ref: ref, dir: dir, clock: clock} = start(fault: fault)

      assert {201, _job} = create(ref, "emails", "k")
      assert {201, _job} = create(ref, "emails", nil)
      assert {200, _job} = decoded(Queue.lease(ref, "emails", 1_000, "bob"))
      assert {200, _job} = decoded(Queue.ack(ref, "j_1", "bob"))
      Clock.advance(clock, @retain)

      # The move is the look's, so the request that took the look is told 503.
      :counters.put(armed, 1, 1)
      assert {:error, :store} = Queue.get(ref, "j_2")

      assert [%{"id" => "j_1", "archived_at" => _at}] = lines(Store.archive_path(dir))
      refute Enum.any?(lines(Store.log_path(dir)), & &1["archived"])

      # The queue read the folder back: the job is archived, counted once, and
      # no later look moves it again.
      assert {200, %{"done" => 0, "archived" => 1, "queued" => 1}} = decoded(Queue.health(ref))
      Clock.advance(clock, @retain)
      assert {200, %{"archived" => 1}} = decoded(Queue.health(ref))
      assert length(lines(Store.archive_path(dir))) == 1
      assert {200, %{"id" => "j_1"}} = create(ref, "emails", "k")

      # A failure before the append leaves the job live, archived at the next look.
      assert {201, _job} = create(ref, "reports", nil, max_tries: 1)
      assert {200, _job} = decoded(Queue.lease(ref, "reports", 1_000, "bob"))
      assert {200, _job} = decoded(Queue.fail(ref, "j_3", "bob", "no"))
      Clock.advance(clock, @retain)
      :counters.put(armed, 1, 2)
      assert {:error, :store} = Queue.get(ref, "j_3")
      assert length(lines(Store.archive_path(dir))) == 1
      assert {200, %{"state" => "dead"}} = decoded(Queue.get(ref, "j_3"))
      assert {200, %{"dead" => 0, "archived" => 2}} = decoded(Queue.health(ref))
      assert [_j1, %{"id" => "j_3"}] = lines(Store.archive_path(dir))
      assert :ok = Never.check(dir)
    end

    test "under kills and failing batches with a small retain_ms, nothing is lost or counted twice" do
      flag = :counters.new(1, [])

      fault = fn batch ->
        cond do
          :counters.get(flag, 1) == 0 -> false
          rem(batch, 7) == 0 -> :between
          rem(batch, 11) == 0 -> true
          true -> false
        end
      end

      %{ref: ref, dir: dir, pid: pid, clock: clock} =
        Service.start(fault: fault, retain_ms: 1, max_restarts: 100)

      :counters.put(flag, 1, 1)

      created =
        for round <- 1..200, reduce: MapSet.new() do
          created ->
            created =
              case settled(ref, fn -> create(ref, "load", "k#{round}", max_tries: 1) end) do
                {status, %{"id" => id}} when status in [200, 201] -> MapSet.put(created, id)
                _other -> created
              end

            with {200, %{"id" => id}} <-
                   settled(ref, fn -> decoded(Queue.lease(ref, "load", 1_000, "w")) end) do
              if rem(round, 3) == 0,
                do: settled(ref, fn -> decoded(Queue.fail(ref, id, "w", "no")) end),
                else: settled(ref, fn -> decoded(Queue.ack(ref, id, "w")) end)
            end

            Clock.advance(clock, 1)

            if rem(round, 17) == 0 do
              kill(ref, :store)
              wait_health(ref)
            end

            created
        end

      # The leases run out (the last try: dead), and a millisecond later the
      # dead are due.
      :counters.put(flag, 1, 0)
      Clock.advance(clock, 2_000)
      {200, _health} = wait_health(ref)
      Clock.advance(clock, 1)
      {200, health} = wait_health(ref)
      Service.stop(pid)

      assert {:ok, %{jobs: jobs, archived: archived}} = Store.open(dir)
      live = MapSet.new(Map.values(jobs), &Job.id/1)
      gone = MapSet.new(Map.values(archived), &Job.id/1)

      # Everything a 2xx reported is on the board or in the archive, never both.
      assert MapSet.disjoint?(live, gone)
      assert MapSet.subset?(created, MapSet.union(live, gone))
      assert health["archived"] == MapSet.size(gone)
      assert Enum.all?(Map.values(jobs), &(&1.state in [:queued, :leased, :scheduled]))
      assert MapSet.size(gone) > 100
      assert :ok = Never.check(dir)

      # A key never names two jobs, and each archived key still answers.
      %{ref: ref} = Service.start(dir: dir, clock: clock, retain_ms: 1_000)

      for job <- Enum.take(Map.values(archived), 20) do
        assert {200, %{"id" => id}} = create(ref, "load", job.key)
        assert id == Job.id(job)
      end
    end
  end

  describe "the store's archive file" do
    test "a folder with no archive is an empty one, and a torn last line is cut" do
      dir = Service.tmp_dir()
      assert {:ok, %{archived: archived}} = Store.open(dir)
      assert archived == %{}

      write(Store.archive_path(dir), [job(1, state: :done, tries: 1, archived_at: 1)])
      File.write!(Store.archive_path(dir), ~s({"id":"j_2","queue":"ema), [:append])
      assert {:ok, %{archived: archived, next: 2}} = Store.open(dir)
      assert Map.keys(archived) == [1]

      %{ref: ref} = Service.start(dir: dir)
      assert {200, %{"archived" => 1}} = decoded(Queue.health(ref))
      assert File.read!(Store.archive_path(dir)) |> String.ends_with?("}\n")
    end

    test "a bad archive record, or a line that is not JSON, refuses the folder" do
      dir = Service.tmp_dir()
      write(Store.archive_path(dir), [job(1, state: :leased, tries: 1, archived_at: 1)])
      assert {:error, {:record, "j_1", _rule}} = Store.open(dir)
      assert {:error, {:record, "j_1", _rule}} = Store.compact(dir)

      File.write!(Store.archive_path(dir), "[]\n")
      assert {:error, {:corrupt_archive, 1}} = Store.open(dir)
    end
  end

  # Helpers

  defp create(ref, queue, key, opts \\ []) do
    ref
    |> Queue.create(
      queue,
      Keyword.get(opts, :payload, "p"),
      Keyword.get(opts, :max_tries, 2),
      Keyword.get(opts, :delay_ms, 0),
      0,
      key
    )
    |> decoded()
  end

  defp decoded({:error, :store}), do: {:error, :store}
  defp decoded({status, nil}), do: {status, nil}
  defp decoded({status, body}), do: {status, JSON.decode!(Json.encode(body))}

  # A service whose idle look waits, so the look that moves a job is the one
  # the test's own request takes.
  defp start(opts), do: Service.start([retain_ms: @retain, sweep_ms: 3_600_000] ++ opts)

  defp kill(ref, name) do
    case Jobq.Registry.whereis(ref, name) do
      nil -> :ok
      pid -> Process.exit(pid, :kill)
    end
  end

  defp settled(ref, request) do
    case request.() do
      {:error, :store} ->
        wait_health(ref)
        :failed

      other ->
        other
    end
  end

  defp wait_health(ref, tries \\ 200) do
    case decoded(Queue.health(ref)) do
      {200, body} ->
        {200, body}

      _other when tries > 0 ->
        Process.sleep(10)
        wait_health(ref, tries - 1)
    end
  end

  defp assert_keys(ref) do
    assert {200, %{"id" => "j_1"}} = create(ref, "emails", "a")
    assert {200, %{"id" => "j_2", "state" => "done"}} = create(ref, "emails", "b")
    assert {200, %{"id" => "j_4", "archived_at" => _at}} = create(ref, "emails", "d")
    assert {201, %{"key" => "c"} = fresh} = create(ref, "emails", "c")
    assert {204, nil} = Queue.delete(ref, fresh["id"])
  end

  defp lines(path) do
    case File.read(path) do
      {:ok, text} -> text |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
      {:error, :enoent} -> []
    end
  end

  defp write(path, records) do
    lines =
      Enum.map(records, fn
        %Job{} = job -> [Json.encode(Job.record(job)), "\n"]
        record -> [Json.encode(record), "\n"]
      end)

    File.write!(path, lines, [:append])
  end

  defp job(n, fields \\ []) do
    %Job{
      n: n,
      queue: "emails",
      payload: "hi",
      max_tries: 3,
      tries: Keyword.get(fields, :tries, 0),
      state: Keyword.get(fields, :state, :queued),
      key: Keyword.get(fields, :key),
      archived_at: Keyword.get(fields, :archived_at),
      created_at: 1_789_000_000_000,
      updated_at: Keyword.get(fields, :updated_at, 1_789_000_000_000)
    }
  end
end
