defmodule Jobq.Change6Test do
  @moduledoc """
  Change 6: the archive pruned, the bench, the rename rule's `next_id`, and a
  folder the change-5 program wrote.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Jobq.Bench
  alias Jobq.CLI
  alias Jobq.Job
  alias Jobq.Json
  alias Jobq.Prune
  alias Jobq.Queue
  alias Jobq.Store
  alias Jobq.Test.Api
  alias Jobq.Test.Clock
  alias Jobq.Test.Never
  alias Jobq.Test.Service

  import ExUnit.CaptureIO

  @retain 60_000
  @t0 1_789_000_000_000

  @moduletag capture_log: true

  describe "the prune, as a pure step" do
    test "removes the jobs at or before the cutoff and frees their keys, and nothing else" do
      old = job(1, state: :done, key: "k1", archived_at: 1_000)
      edge = job(2, state: :dead, key: "k2", archived_at: 2_000)
      young = job(3, state: :done, key: "k3", archived_at: 2_001)
      # A key the queue gave a later job is that job's, not the pruned one's.
      reused = job(4, state: :done, key: "k4", archived_at: 500)
      archived = %{1 => old, 2 => edge, 3 => young, 4 => reused}

      keys = %{
        {"emails", "k1"} => 1,
        {"emails", "k2"} => 2,
        {"emails", "k3"} => 3,
        {"emails", "k4"} => 9,
        {"other", "k1"} => 7
      }

      assert {kept, keys_after, gone} = Prune.step(archived, keys, 2_000)
      assert kept == %{3 => young}
      assert gone |> Enum.map(& &1.n) |> Enum.sort() == [1, 2, 4]
      assert keys_after == %{{"emails", "k3"} => 3, {"emails", "k4"} => 9, {"other", "k1"} => 7}
    end

    test "requires an age of at least a second" do
      assert Prune.cutoff(10_000, 1_000) == 9_000
      assert_raise FunctionClauseError, fn -> Prune.cutoff(10_000, 999) end
    end

    property "ensures: every job removed is at or before the cutoff, every job kept after it, and only removed jobs' keys go" do
      check all(
              ats <- list_of(integer(0..10_000), max_length: 30),
              cutoff <- integer(0..10_000)
            ) do
        archived =
          ats
          |> Enum.with_index(1)
          |> Map.new(fn {at, n} -> {n, job(n, state: :done, key: "k#{n}", archived_at: at)} end)

        keys = Map.new(archived, fn {n, job} -> {{job.queue, job.key}, n} end)
        {kept, keys_after, gone} = Prune.step(archived, keys, cutoff)

        assert Enum.all?(gone, &(&1.archived_at <= cutoff))
        assert Enum.all?(kept, fn {_n, job} -> job.archived_at > cutoff end)
        assert map_size(kept) + length(gone) == map_size(archived)
        assert keys_after == Map.new(kept, fn {n, job} -> {{job.queue, job.key}, n} end)
      end
    end

    test "a prune record's shape" do
      assert :ok = Prune.check_record(%{"prune" => 5, "count" => 1})

      assert {:error, "a prune's cutoff" <> _} =
               Prune.check_record(%{"prune" => -1, "count" => 1})

      assert {:error, "a prune's cutoff" <> _} =
               Prune.check_record(%{"prune" => "5", "count" => 1})

      assert {:error, "a prune's count" <> _} = Prune.check_record(%{"prune" => 5, "count" => 0})
      assert {:error, "a prune's count" <> _} = Prune.check_record(%{"prune" => 5})

      assert {:error, "a prune has no id"} =
               Prune.check_record(%{"prune" => 5, "count" => 1, "id" => "j_1"})
    end
  end

  describe "POST /archive/prune and GET /archive" do
    test "removes the old archived jobs in one record before the response, and frees their keys" do
      %{ref: ref, port: port, dir: dir, clock: clock} = two_archived()
      # A done job not yet archived, and a live job.
      finish(ref, "emails", "j_3")
      create(ref, "emails", "live")

      assert {200, %{"archived" => 2, "oldest_archived_at" => oldest, "bytes" => bytes}} =
               Api.request(port, "t", "GET", "/archive")

      assert oldest == Jobq.Clock.iso8601(@t0 + @retain)
      assert bytes == File.stat!(Store.archive_path(dir)).size
      log_before = lines(Store.log_path(dir))

      assert {200, %{"pruned" => 1, "remaining" => 1}} = prune(port, 5_000)

      # One record, on the disk before the response, naming the cutoff.
      now = Clock.now(clock)
      assert lines(Store.log_path(dir)) == log_before ++ [%{"prune" => now - 5_000, "count" => 1}]

      assert {404, _} = Api.request(port, "t", "GET", "/jobs/j_1")
      assert {200, %{"archived_at" => _}} = Api.request(port, "t", "GET", "/jobs/j_2")
      assert {200, %{"state" => "done"}} = Api.request(port, "t", "GET", "/jobs/j_3")
      assert {200, %{"state" => "queued"}} = Api.request(port, "t", "GET", "/jobs/j_4")
      assert {200, %{"archived" => 1, "done" => 1, "queued" => 1}} = decoded(Queue.health(ref))

      assert {200, %{"archived" => 1, "oldest_archived_at" => oldest}} =
               Api.request(port, "t", "GET", "/archive")

      assert oldest == Jobq.Clock.iso8601(@t0 + 2 * @retain)

      # j_1's key is free: a create with it is a new job; j_2's is still held.
      assert {201, %{"id" => "j_5"}} = create(ref, "emails", "k1")
      assert {200, %{"id" => "j_2"}} = create(ref, "emails", "k2")
      assert {200, %{"jobs" => []}} = Api.request(port, "t", "GET", "/jobs?queue=emails&key=k2")
      assert :ok = Never.check(dir)
    end

    test "a prune that removes nothing answers 0 and writes nothing" do
      %{port: port, dir: dir} = two_archived()
      before = File.read!(Store.log_path(dir))

      assert {200, %{"pruned" => 0, "remaining" => 2}} = prune(port, 3_600_000)
      assert File.read!(Store.log_path(dir)) == before
    end

    test "an empty archive, and the requests it refuses" do
      %{port: port} = start([])

      assert {200, %{"archived" => 0, "oldest_archived_at" => nil, "bytes" => 0}} =
               Api.request(port, "t", "GET", "/archive")

      assert {200, %{"pruned" => 0, "remaining" => 0}} = prune(port, 1_000)

      assert {400, %{"error" => "older_than_ms must be a whole number of at least 1000"}} =
               prune(port, 999)

      assert {400, _} = prune_body(port, ~s({"older_than_ms":"5000"}))
      assert {400, _} = prune_body(port, ~s({"older_than_ms":1500.5}))
      assert {400, %{"error" => "'older_than_ms' is required"}} = prune_body(port, "{}")
      assert {400, _} = prune_body(port, ~s({"older_than_ms":5000,"x":1}))
      assert {400, _} = prune_body(port, "nope")
      assert {405, _} = Api.request(port, "t", "GET", "/archive/prune")
      assert {405, _} = Api.request(port, "t", "POST", "/archive")
      assert {401, _} = Api.request(port, "", "GET", "/archive")
    end

    test "a pruned job stays gone across a restart and a compaction, and the counts hold" do
      %{ref: ref, port: port, dir: dir, pid: pid} = two_archived()
      assert {200, %{"pruned" => 1}} = prune(port, 5_000)
      assert {201, %{"id" => "j_4"}} = create(ref, "emails", "k1")
      Service.stop(pid)

      assert {:ok, folder} = Store.open(dir)
      assert Map.keys(folder.archived) == [2]
      assert folder.next == 5
      assert %{"archived" => 1} = verify_counts(dir)

      assert {:ok, 2} = Store.compact(dir)
      refute File.read!(Store.log_path(dir)) =~ "prune"
      refute File.read!(Store.archive_path(dir)) =~ ~s("id":"j_1")
      assert {:ok, ^folder} = Store.open(dir)

      %{ref: ref} = Service.start(dir: dir, retain_ms: @retain, sweep_ms: 3_600_000)
      assert {404, _} = decoded(Queue.get(ref, "j_1"))
      assert {200, %{"id" => "j_4"}} = create(ref, "emails", "k1")
      assert {200, %{"id" => "j_2"}} = create(ref, "emails", "k2")
      assert {201, %{"id" => "j_5"}} = create(ref, "emails", "k9")
      assert {200, %{"archived" => 1}} = decoded(Queue.health(ref))
    end

    test "a kill anywhere in the prune record leaves it wholly on the disk or wholly off" do
      %{port: port, dir: dir, pid: pid} = two_archived()
      assert {200, %{"pruned" => 1}} = prune(port, 5_000)
      Service.stop(pid)

      bytes = File.read!(Store.log_path(dir))
      [{at, length}] = Regex.run(~r/\{"prune":\d+,"count":1\}\n/, bytes, return: :index)

      for cut <- at..(at + length) do
        File.write!(Store.log_path(dir), binary_part(bytes, 0, cut))
        assert {:ok, folder} = Store.open(dir)

        if cut == at + length,
          do: assert(Map.keys(folder.archived) == [2]),
          else: assert(Map.keys(folder.archived) == [1, 2])
      end
    end

    test "the replay applies a prune to what the log sent off before it, and not to a job it names after" do
      dir = Service.tmp_dir()
      done = fn n -> job(n, state: :done, tries: 1, updated_at: 100) end

      # j_1 left the log before the prune; j_2 after it, although its
      # archived_at (set by a clock that went back) is before the cutoff;
      # j_3 was left in both files by a kill between a move's two writes
      # before the prune; j_4 is live and older than everything.
      write(Store.log_path(dir), [
        done.(1),
        %{"id" => "j_1", "archived" => true},
        done.(2),
        done.(3),
        job(4, updated_at: 1),
        %{"prune" => 1_000, "count" => 2},
        %{"id" => "j_2", "archived" => true}
      ])

      write(Store.archive_path(dir), [
        %{done.(1) | archived_at: 900},
        %{done.(2) | archived_at: 900},
        %{done.(3) | archived_at: 1_000}
      ])

      assert {:ok, folder} = Store.open(dir)
      assert Map.keys(folder.archived) == [2]
      assert Map.keys(folder.jobs) == [4]
      assert folder.next == 5

      assert {:ok, 1} = Store.compact(dir)
      assert {:ok, ^folder} = Store.open(dir)
    end

    test "a compaction killed after any of its steps leaves the pruned job gone and the names as they were" do
      for step <- [:tombstones, :log, :archive] do
        %{port: port, dir: dir, pid: pid} = two_archived()
        assert {200, _} = rename(port, "emails", "mail")
        assert {200, %{"pruned" => 1}} = prune(port, 5_000)
        Service.stop(pid)
        assert {:ok, before} = Store.open(dir)

        assert catch_throw(Store.compact(dir, stop_at: stop_at(step))) == {:killed, step}
        assert {:ok, ^before} = Store.open(dir)
        assert %{2 => %Job{queue: "mail"}} = before.archived
        assert {:ok, 1} = Store.compact(dir)
        assert {:ok, ^before} = Store.open(dir)
      end
    end
  end

  describe "the background prune" do
    test "prunes on its tick with the service's retention, one record, and writes nothing when nothing is due" do
      %{ref: ref, dir: dir, clock: clock} =
        start(retention_ms: 20_000, prune_every_ms: 10)

      create(ref, "emails", "k1")
      finish(ref, "emails", "j_1")
      Clock.advance(clock, @retain)
      assert {200, %{"archived" => 1}} = decoded(Queue.health(ref))

      # Younger than the retention: ticks go by, nothing is written.
      Clock.advance(clock, 19_999)
      Process.sleep(60)
      assert {200, %{"archived" => 1}} = decoded(Queue.health(ref))
      refute File.read!(Store.log_path(dir)) =~ "prune"

      Clock.advance(clock, 1)
      assert wait_until(fn -> match?({200, %{"archived" => 0}}, decoded(Queue.health(ref))) end)
      Process.sleep(60)

      prunes = dir |> Store.log_path() |> lines() |> Enum.filter(&Map.has_key?(&1, "prune"))
      assert prunes == [%{"prune" => Clock.now(clock) - 20_000, "count" => 1}]
      assert {201, %{"id" => "j_2"}} = create(ref, "emails", "k1")
    end

    test "is off by default" do
      %{ref: ref, dir: dir, clock: clock} = start(prune_every_ms: 10)
      create(ref, "emails", "k1")
      finish(ref, "emails", "j_1")
      Clock.advance(clock, 100 * @retain)
      assert {200, %{"archived" => 1}} = decoded(Queue.health(ref))
      Process.sleep(60)
      assert {200, %{"archived" => 1}} = decoded(Queue.health(ref))
      refute File.read!(Store.log_path(dir)) =~ "prune"
    end
  end

  describe "the rename's next_id" do
    test "a job created into the old name after the rename, and archived later, stays in the old name" do
      %{ref: ref, port: port, dir: dir, clock: clock, pid: pid} = start([])
      create(ref, "a", "k")
      finish(ref, "a", "j_1")
      Clock.advance(clock, @retain)
      create(ref, "a", "live")

      assert {200, %{"moved" => 2}} = rename(port, "a", "b")

      assert %{"rename" => "a", "to" => "b", "next_id" => 3} =
               List.last(lines(Store.log_path(dir)))

      # The old name is a fresh queue, and its keys are its own.
      assert {201, %{"id" => "j_3", "queue" => "a"}} = create(ref, "a", "k")
      finish(ref, "a", "j_3")
      Clock.advance(clock, @retain)
      assert {200, %{"archived" => 2}} = decoded(Queue.health(ref))
      Service.stop(pid)

      expected = %{1 => "b", 3 => "a"}
      assert {:ok, folder} = Store.open(dir)
      assert names(folder.archived) == expected
      assert names(folder.jobs) == %{2 => "b"}

      assert {:ok, 1} = Store.compact(dir)
      refute File.read!(Store.log_path(dir)) =~ "rename"
      assert {:ok, ^folder} = Store.open(dir)

      %{ref: ref} = Service.start(dir: dir, retain_ms: @retain, sweep_ms: 3_600_000)
      assert {200, %{"id" => "j_1", "queue" => "b"}} = create(ref, "b", "k")
      assert {200, %{"id" => "j_3", "queue" => "a"}} = create(ref, "a", "k")
    end

    test "the replay moves only the jobs below next_id, on the log and in the archive" do
      dir = Service.tmp_dir()
      done = fn n -> %{job(n, state: :done, tries: 1) | queue: "a"} end

      # j_1 archived before the rename and compacted off the log (it is only in
      # the archive); j_2 live; j_3 archived under "a" and named on the log
      # before the rename; the rename at next_id 4; j_4 into "a" after it.
      write(Store.archive_path(dir), [%{done.(1) | archived_at: 5}, %{done.(3) | archived_at: 5}])

      write(Store.log_path(dir), [
        %{"next" => 2},
        %{job(2) | queue: "a"},
        done.(3),
        %{"id" => "j_3", "archived" => true},
        %{"rename" => "a", "to" => "b", "next_id" => 4},
        %{job(4) | queue: "a"}
      ])

      assert {:ok, folder} = Store.open(dir)
      assert names(folder.archived) == %{1 => "b", 3 => "b"}
      assert names(folder.jobs) == %{2 => "b", 4 => "a"}
    end

    test "a rename record with a bad next_id refuses the folder" do
      dir = Service.tmp_dir()
      write(Store.log_path(dir), [job(1), %{"rename" => "emails", "to" => "b", "next_id" => 0}])

      assert {:error,
              {:record, ~s(rename "emails"), "a rename's next_id is a whole number of at least 1"}} =
               Store.open(dir)
    end
  end

  describe "a folder the change-5 program wrote" do
    test "opens, with its rename record read as reaching every job the folder had then" do
      dir = change5_folder()
      log = File.read!(Store.log_path(dir))
      # The change-5 program wrote its rename without a next_id, after a compaction.
      assert log =~ ~s({"rename":"older","to":"eldest"}\n)

      assert {:ok, folder} = Store.open(dir)
      assert names(folder.jobs) == %{2 => "eldest", 3 => "eldest", 5 => "older"}
      assert names(folder.archived) == %{1 => "eldest", 4 => "old"}
      assert folder.next == 6

      assert {0,
              "3 jobs: queued 3, scheduled 0, leased 0, done 0, dead 0; next id j_6; archived 2\n"} =
               run_cli(["verify", dir])

      %{ref: ref, pid: pid} = Service.start(dir: dir, retain_ms: @retain, sweep_ms: 3_600_000)
      assert {200, %{"id" => "j_1", "queue" => "eldest"}} = create(ref, "eldest", "k1")
      assert {200, %{"id" => "j_2", "queue" => "eldest"}} = create(ref, "eldest", "k2")
      assert {200, %{"id" => "j_4", "queue" => "old"}} = create(ref, "old", "k1")
      assert {200, %{"id" => "j_5", "queue" => "older"}} = create(ref, "older", "k2")
      assert {200, %{"moved" => 1}} = decoded(Queue.rename(ref, "older", "newer"))
      Service.stop(pid)

      assert {:ok, reopened} = Store.open(dir)
      assert names(reopened.jobs) == %{2 => "eldest", 3 => "eldest", 5 => "newer"}
      assert names(reopened.archived) == names(folder.archived)

      assert {:ok, 3} = Store.compact(dir)
      refute File.read!(Store.log_path(dir)) =~ "rename"
      assert {:ok, ^reopened} = Store.open(dir)
    end

    test "is pruned offline by jobq prune, and verify agrees" do
      dir = change5_folder()

      assert {0, "pruned 2; remaining 0\n"} = run_cli(["prune", dir, "--older-than-ms", "1000"])
      assert %{"count" => 2} = List.last(lines(Store.log_path(dir)))
      assert {0, "pruned 0; remaining 0\n"} = run_cli(["prune", dir, "--older-than-ms", "1000"])
      assert %{"archived" => 0} = verify_counts(dir)

      assert {2, _usage} = run_cli(["prune", dir, "--older-than-ms", "999"])
      assert {2, _usage} = run_cli(["prune", dir])
    end
  end

  describe "the commands" do
    test "serve's --retention is 0 or at least 1000" do
      dir = Service.tmp_dir()
      assert {2, out} = run_cli(["serve", dir, "--retention", "500"])
      assert out =~ "--retention must be 0 or at least 1000"
      assert {2, _out} = run_cli(["serve", dir, "--retention", "x"])
      assert {2, _out} = run_cli(["bench", dir, "--jobs", "0"])
      assert {2, _out} = run_cli(["bench", dir, "--nope", "1"])
    end

    test "prune on a folder that is not one, or that does not open" do
      dir = Service.tmp_dir()
      File.write!(Path.join(dir, "file"), "")
      assert {1, out} = run_cli(["prune", Path.join(dir, "file"), "--older-than-ms", "1000"])
      assert out =~ "cannot open"

      File.write!(Store.log_path(dir), ~s({"prune":-5,"count":1}\n))
      assert {1, out} = run_cli(["prune", dir, "--older-than-ms", "1000"])
      assert out =~ "record prune -5: a prune's cutoff is a whole number of milliseconds"
      assert {1, _out} = run_cli(["verify", dir])
      assert {1, _out} = run_cli(["compact", dir])
    end

    test "bench prints one line per number" do
      dir = Service.tmp_dir()

      start = fn dir, port ->
        %{pid: pid} = Service.start(dir: dir, port: port)
        {:ok, %{port: port, stop: fn -> Service.stop(pid) end, rss_kib: fn -> 1_024 end}}
      end

      out =
        capture_io(fn ->
          assert :ok = Bench.run(dir, jobs: 80, workers: 4, seconds: 1, start: start)
        end)

      for line <- [
            ~r/^load average before: /m,
            ~r/^creates\/s: \d+ \(80 in [\d.]+ s, errors 0\)$/m,
            ~r/^pairs\/s at 1 worker\(s\): \d+ /m,
            ~r/^pairs\/s at 4 worker\(s\): \d+ /m,
            ~r/^rss after pairs: 1\.0 MiB$/m,
            ~r/^restart to \/health: [\d.]+ s /m
          ] do
        assert out =~ line
      end
    end
  end

  describe "the declared errors" do
    test "a full disk is the batch's 503, and the service goes on off the log" do
      full = :counters.new(1, [])

      %{ref: ref, dir: dir} =
        start(
          fault: fn _batch ->
            if :counters.get(full, 1) == 1, do: {:error, :enospc}, else: false
          end
        )

      assert {201, _} = create(ref, "emails", "k1")
      :counters.put(full, 1, 1)
      assert {:error, :store} = Queue.create(ref, "emails", "two", 1)
      :counters.put(full, 1, 0)
      assert {201, %{"id" => "j_2"}} = create(ref, "emails", "k2")
      assert {:ok, {jobs, 3}} = Store.read(dir)
      assert map_size(jobs) == 2
    end
  end

  describe "the declared errors, the ones no earlier test reached" do
    test "a file in the folder that cannot be read refuses the folder" do
      dir = Service.tmp_dir()
      File.mkdir_p!(Store.archive_path(dir))
      assert {:error, {:open, path, :eisdir}} = Store.open(dir)
      assert path == Store.archive_path(dir)
      assert {1, out} = run_cli(["verify", dir])
      assert out =~ "cannot open #{path}"
    end

    test "a log the store cannot open to append stops it at start" do
      Process.flag(:trap_exit, true)
      dir = Service.tmp_dir()
      File.mkdir_p!(Store.log_path(dir))

      assert {:error, reason} =
               Jobq.Server.start_link(ref: make_ref(), dir: dir, port: 0, max_restarts: 0)

      assert inspect(reason) =~ "eisdir"
    end

    test "a reload that finds the folder refused stops the queue, and the board past its budget" do
      Process.flag(:trap_exit, true)
      failing = :counters.new(1, [])

      %{ref: ref, dir: dir, pid: pid} =
        start(max_restarts: 0, fault: fn _batch -> :counters.get(failing, 1) == 1 end)

      assert {201, _} = create(ref, "emails", "k1")
      File.write!(Store.log_path(dir), "not json\n", [:append])
      :counters.put(failing, 1, 1)

      assert {:error, :store} = Queue.create(ref, "emails", "two", 1)
      assert_receive {:EXIT, ^pid, :shutdown}, 5_000
    end

    test "a compaction that cannot write leaves the folder as it was" do
      %{port: port, dir: dir, pid: pid} = two_archived()
      assert {200, %{"pruned" => 1}} = prune(port, 5_000)
      Service.stop(pid)
      log = File.read!(Store.log_path(dir))
      archive = File.read!(Store.archive_path(dir))
      {:ok, before} = Store.open(dir)

      File.mkdir_p!(Store.log_path(dir) <> ".compact")
      assert {:error, {:compact, :eisdir}} = Store.compact(dir)
      assert {1, out} = run_cli(["compact", dir])
      assert out =~ "compact"
      File.rmdir!(Store.log_path(dir) <> ".compact")
      assert File.read!(Store.log_path(dir)) == log
      # The tombstone for the pruned job went in before the log's rewrite.
      assert File.read!(Store.archive_path(dir)) == archive <> ~s({"id":"j_1","deleted":true}\n)
      assert {:ok, ^before} = Store.open(dir)

      File.write!(Store.archive_path(dir), archive)
      File.chmod!(Store.archive_path(dir), 0o444)
      assert {:error, {:compact, :eacces}} = Store.compact(dir)
      assert File.read!(Store.log_path(dir)) == log
      assert {:ok, ^before} = Store.open(dir)
    end

    test "an offline prune that cannot append to the log" do
      dir = change5_folder()
      File.chmod!(Store.log_path(dir), 0o444)

      assert {:error, {:open, _path, :eacces}} =
               Store.prune(dir, 1_000, System.system_time(:millisecond))

      assert {1, out} = run_cli(["prune", dir, "--older-than-ms", "1000"])
      assert out =~ "cannot open"
    end

    test "a bench whose service does not come up, or does not start" do
      dir = Service.tmp_dir()

      nothing = fn _dir, port ->
        {:ok, %{port: port, stop: fn -> :ok end, rss_kib: fn -> 0 end}}
      end

      capture_io(fn ->
        assert {:error, {:no_health, _port}} = Bench.run(dir, start: nothing, up_ms: 100)
        assert {:error, :nope} = Bench.run(dir, start: fn _dir, _port -> {:error, :nope} end)
      end)
    end
  end

  # Helpers

  # j_1 archived at t0 + retain, j_2 (done then) at t0 + 2 retain, j_3 queued;
  # the clock at j_2's archive + 1 s.
  defp two_archived do
    service = start([])
    %{ref: ref, clock: clock} = service
    create(ref, "emails", "k1")
    create(ref, "emails", "k2")
    finish(ref, "emails", "j_1")
    Clock.advance(clock, @retain)
    assert {200, %{"archived" => 1}} = decoded(Queue.health(ref))
    finish(ref, "emails", "j_2")
    Clock.advance(clock, 10_000)
    create(ref, "emails", "k3")
    Clock.advance(clock, @retain - 10_000)
    assert {200, %{"archived" => 2}} = decoded(Queue.health(ref))
    Clock.advance(clock, 1_000)
    service
  end

  defp change5_folder do
    dir = Service.tmp_dir()
    File.cp_r!("test/fixtures/change5/data", dir)
    dir
  end

  defp stop_at(step) do
    fn
      ^step -> throw({:killed, step})
      _other -> :ok
    end
  end

  defp finish(ref, queue, id) do
    {200, %{"id" => ^id}} = decoded(Queue.lease(ref, queue, 1_000, "w"))
    {200, %{"state" => "done"}} = decoded(Queue.ack(ref, id, "w"))
  end

  defp create(ref, queue, key),
    do: decoded(Queue.create(ref, queue, "payload", 1, 0, 0, key))

  defp prune(port, age), do: prune_body(port, ~s({"older_than_ms":#{age}}))
  defp prune_body(port, body), do: Api.request(port, "op", "POST", "/archive/prune", body)

  defp rename(port, from, to),
    do: Api.request(port, "op", "POST", "/queues/#{from}/rename", ~s({"to":"#{to}"}))

  defp verify_counts(dir) do
    {0, out} = run_cli(["verify", dir])
    [_all, archived] = Regex.run(~r/archived (\d+)/, out)
    %{"archived" => String.to_integer(archived)}
  end

  defp names(jobs), do: Map.new(jobs, fn {n, job} -> {n, job.queue} end)

  defp decoded({:error, :store}), do: {:error, :store}
  defp decoded({status, nil}), do: {status, nil}
  defp decoded({status, body}), do: {status, JSON.decode!(Json.encode(body))}

  defp start(opts), do: Service.start([retain_ms: @retain, sweep_ms: 3_600_000] ++ opts)

  defp wait_until(check, tries \\ 200) do
    cond do
      check.() -> true
      tries == 0 -> false
      true -> Process.sleep(10) || wait_until(check, tries - 1)
    end
  end

  # The capture of stderr is shared by every async test writing to it at the
  # time, so a success is read by its stdout alone; a refusal is only ever
  # matched with =~.
  defp run_cli(argv) do
    {{status, stdout}, stderr} =
      with_io(:stderr, fn -> with_io(fn -> CLI.run(argv) end) end)

    case status do
      0 -> {status, stdout}
      _failed -> {status, stdout <> stderr}
    end
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
