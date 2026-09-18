defmodule Jobq.Change5Test do
  @moduledoc """
  Change 5: a lease handed to another worker, and a queue renamed with jobs in
  flight.
  """

  use ExUnit.Case, async: true

  alias Jobq.CLI
  alias Jobq.Handoff
  alias Jobq.Job
  alias Jobq.Json
  alias Jobq.Queue
  alias Jobq.Rename
  alias Jobq.Store
  alias Jobq.Test.Api
  alias Jobq.Test.Clock
  alias Jobq.Test.Never
  alias Jobq.Test.Service

  import ExUnit.CaptureIO

  @retain 60_000

  @moduletag capture_log: true

  describe "the handoff, as a pure step" do
    test "requires the caller's lease, and ensures the lease moved with tries and lease_until kept" do
      leased = %{job(1, state: :leased, tries: 2) | worker: "a", lease_until: 5_000}

      assert {:ok, handed, true} = Handoff.step(leased, "a", "b", 99)
      assert handed == %{leased | worker: "b", updated_at: 99}
      assert {:ok, ^leased, false} = Handoff.step(leased, "a", "a", 99)
      assert :not_held = Handoff.step(leased, "b", "c", 99)
      assert :not_held = Handoff.step(job(2), "a", "b", 99)
      assert :not_held = Handoff.step(%{leased | state: :done}, "a", "b", 99)
    end
  end

  describe "the handoff" do
    test "from the holder: the job is the new worker's, lease and tries as they were" do
      %{ref: ref, port: port, dir: dir, clock: clock} = start([])
      create(ref, "emails", nil)
      {200, leased} = decoded(Queue.lease(ref, "emails", 10_000, "a"))
      Clock.advance(clock, 5)

      assert {200, handed} = handoff(port, "a", "j_1", "b")
      assert handed["worker"] == "b"
      assert handed["state"] == "leased"

      assert Map.take(handed, ["lease_until", "tries"]) ==
               Map.take(leased, ["lease_until", "tries"])

      assert handed["updated_at"] != leased["updated_at"]

      # On the disk before the response.
      assert %{"worker" => "b", "state" => "leased"} = List.last(lines(Store.log_path(dir)))

      assert {409, _} = Api.request(port, "a", "POST", "/jobs/j_1/ack")
      assert {409, _} = Api.request(port, "a", "POST", "/jobs/j_1/fail")
      assert {409, _} = handoff(port, "a", "j_1", "a")
      assert {200, %{"state" => "done"}} = Api.request(port, "b", "POST", "/jobs/j_1/ack")
      assert :ok = Never.check(dir)
    end

    test "from a stranger, on no job, after the lease ran out, and with a bad to" do
      %{ref: ref, port: port, clock: clock} = start([])
      create(ref, "emails", nil)
      create(ref, "emails", nil)

      assert {409, _} = handoff(port, "a", "j_1", "b")
      {200, _} = decoded(Queue.lease(ref, "emails", 1_000, "a"))
      assert {409, _} = handoff(port, "c", "j_1", "b")
      assert {404, _} = handoff(port, "a", "j_9", "b")
      assert {404, _} = handoff(port, "a", "nope", "b")

      assert {400, %{"error" => "to must have no whitespace"}} = handoff(port, "a", "j_1", "b c")

      assert {400, %{"error" => "to must be 1 to 128 bytes"}} =
               handoff(port, "a", "j_1", String.duplicate("x", 129))

      assert {400, _} = handoff(port, "a", "j_1", "")

      assert {400, %{"error" => "to must be a string"}} =
               handoff_body(port, "a", "j_1", ~s({"to":7}))

      assert {400, %{"error" => "'to' is required"}} = handoff_body(port, "a", "j_1", "{}")
      assert {400, _} = handoff_body(port, "a", "j_1", ~s({"to":"b","x":1}))
      assert {405, _} = Api.request(port, "a", "GET", "/jobs/j_1/handoff")
      assert {200, _} = handoff(port, "a", "j_1", String.duplicate("x", 128))

      {200, _} = decoded(Queue.lease(ref, "emails", 1_000, "a"))
      Clock.advance(clock, 1_000)
      assert {409, _} = handoff(port, "a", "j_2", "b")
      assert {200, %{"state" => "queued"}} = decoded(Queue.get(ref, "j_2"))
    end

    test "to the holder itself is 200 and writes nothing" do
      %{ref: ref, port: port, dir: dir} = start([])
      create(ref, "emails", nil)
      {200, leased} = decoded(Queue.lease(ref, "emails", 1_000, "a"))
      before = lines(Store.log_path(dir))

      assert {200, ^leased} = handoff(port, "a", "j_1", "a")
      assert lines(Store.log_path(dir)) == before
    end

    test "twice in a row: A to B, B to C; A's and B's ack are 409, C's is 200" do
      %{ref: ref, port: port, dir: dir} = start([])
      create(ref, "emails", nil)
      {200, _} = decoded(Queue.lease(ref, "emails", 1_000, "A"))

      assert {200, %{"worker" => "B"}} = handoff(port, "A", "j_1", "B")
      assert {200, %{"worker" => "C"}} = handoff(port, "B", "j_1", "C")
      assert {409, _} = handoff(port, "A", "j_1", "D")
      assert {409, _} = Api.request(port, "A", "POST", "/jobs/j_1/ack")
      assert {409, _} = Api.request(port, "B", "POST", "/jobs/j_1/ack")

      assert {200, %{"state" => "done", "tries" => 1}} =
               Api.request(port, "C", "POST", "/jobs/j_1/ack")

      assert :ok = Never.check(dir)
    end

    test "across a restart and a compaction the job is the new worker's, with the same lease_until" do
      %{ref: ref, dir: dir, pid: pid, clock: clock} = start([])
      create(ref, "emails", nil)
      {200, leased} = decoded(Queue.lease(ref, "emails", 60_000, "a"))
      {200, _} = decoded(Queue.handoff(ref, "j_1", "a", "b"))

      Service.stop(pid)
      %{ref: ref, pid: pid} = start(dir: dir, clock: clock)
      assert {200, got} = decoded(Queue.get(ref, "j_1"))
      assert got["worker"] == "b"
      assert got["lease_until"] == leased["lease_until"]
      assert {409, _} = decoded(Queue.fail(ref, "j_1", "a", nil))

      Service.stop(pid)
      assert {:ok, 1} = Store.compact(dir)
      %{ref: ref} = start(dir: dir, clock: clock)
      assert {200, %{"worker" => "b"}} = decoded(Queue.get(ref, "j_1"))

      assert {200, %{"state" => "queued", "tries" => 1}} =
               decoded(Queue.fail(ref, "j_1", "b", nil))
    end

    test "a handoff is a write the chaos switch counts, and the board comes back with it" do
      # Writes: the create, the lease, the handoff.
      %{ref: ref} = start(crash: fn write -> write == 3 end, max_restarts: 5)
      create(ref, "emails", nil)
      {200, _} = decoded(Queue.lease(ref, "emails", 60_000, "a"))
      assert {:error, :store} = decoded(Queue.handoff(ref, "j_1", "a", "b"))

      assert {200, %{"restarts" => 1}} = wait_health(ref)
      assert {200, %{"worker" => "b"}} = decoded(Queue.get(ref, "j_1"))
      assert {409, _} = decoded(Queue.ack(ref, "j_1", "a"))
      assert {200, _} = decoded(Queue.ack(ref, "j_1", "b"))
    end
  end

  describe "the rename, as a pure step" do
    test "checks the names, and moves the jobs and the keys of one queue only" do
      a1 = job(1, key: "k")
      a2 = %{job(2, state: :done, tries: 1, key: "m") | archived_at: 5}
      b3 = %{job(3, key: "k") | queue: "other"}
      live = %{1 => a1, 3 => b3}
      archived = %{2 => a2}
      keys = %{{"emails", "k"} => 1, {"emails", "m"} => 2, {"other", "k"} => 3}

      assert :ok = Rename.check([live, archived], "emails", "mail")
      assert :not_found = Rename.check([live, archived], "nobody", "mail")
      assert :exists = Rename.check([live, archived], "emails", "other")
      assert :exists = Rename.check([live, archived], "emails", "emails")
      assert :exists = Rename.check([%{}, archived], "emails", "emails")
      # A queue with only an archived job is a queue, for both names.
      assert :ok = Rename.check([%{}, archived], "emails", "mail")
      assert :exists = Rename.check([live, archived], "other", "emails")

      assert {moved, 1} = Rename.jobs(live, "emails", "mail", 4)
      assert moved == %{1 => %{a1 | queue: "mail"}, 3 => b3}

      assert {%{2 => %Job{queue: "mail", archived_at: 5}}, 1} =
               Rename.jobs(archived, "emails", "mail", 4)

      assert Rename.keys(keys, "emails", "mail") ==
               %{{"mail", "k"} => 1, {"mail", "m"} => 2, {"other", "k"} => 3}

      # The clash needs no code: `check` refused "other" as a target because it
      # has a job, and a key names a job, so a target that passes has no key.
      # Renaming "emails" onto "other" would have put two jobs under
      # {"other", "k"}, which is exactly the rename `check` refused above.
      refute Enum.any?(Map.keys(keys), fn {queue, _key} -> queue == "mail" end)
    end

    test "a name after renames, in order" do
      assert Rename.apply_all("a", 1, [{"a", "b", 9}, {"b", "c", 9}]) == "c"
      assert Rename.apply_all("a", 1, [{"b", "c", 9}, {"a", "b", 9}]) == "b"
      assert Rename.apply_all("a", 1, [{"a", "b", 9}, {"b", "a", 9}]) == "a"
      assert Rename.apply_all("z", 1, [{"a", "b", 9}]) == "z"
    end

    test "a rename record's rule" do
      assert :ok = Rename.check_record(%{"rename" => "a", "to" => "b"})

      assert {:error, "a rename's to: queue must be letters, digits, '-' or '_'"} =
               Rename.check_record(%{"rename" => "a", "to" => "b c"})

      assert {:error, "a rename's rename: queue must be a string"} =
               Rename.check_record(%{"rename" => 1, "to" => "b"})

      assert {:error, "a rename's to: queue must be a string"} =
               Rename.check_record(%{"rename" => "a"})

      assert {:error, "a rename names two different queues"} =
               Rename.check_record(%{"rename" => "a", "to" => "a"})

      assert {:error, "a rename has no id"} =
               Rename.check_record(%{"rename" => "a", "to" => "b", "id" => "j_1"})
    end
  end

  describe "the rename" do
    test "moves every job in every state, keys and a lease in flight included, in one record" do
      %{ref: ref, port: port, dir: dir, clock: clock} = start([])

      # j_1 archived, j_2 done, j_3 dead, j_4 leased, j_5 scheduled, j_6 queued,
      # j_7 in another queue.
      for key <- ~w(k1 k2 k3 k4) do
        create(ref, "emails", key, max_tries: 1)
      end

      {200, _} = decoded(Queue.lease(ref, "emails", 1_000, "w"))
      {200, _} = decoded(Queue.ack(ref, "j_1", "w"))
      Clock.advance(clock, @retain)
      {200, %{"archived" => 1}} = decoded(Queue.health(ref))
      {200, _} = decoded(Queue.lease(ref, "emails", 1_000, "w"))
      {200, _} = decoded(Queue.ack(ref, "j_2", "w"))
      {200, _} = decoded(Queue.lease(ref, "emails", 1_000, "w"))
      {200, _} = decoded(Queue.fail(ref, "j_3", "w", "no"))
      {200, leased} = decoded(Queue.lease(ref, "emails", 60_000, "w"))
      create(ref, "emails", "k5", delay_ms: 1_000_000)
      create(ref, "emails", "k6")
      create(ref, "other", "k1")
      {200, %{"queues" => before}} = decoded(Queue.queues(ref))
      emails_row = Enum.find(before, &(&1["name"] == "emails"))
      log_before = lines(Store.log_path(dir))
      archive_before = File.read!(Store.archive_path(dir))

      assert {200, %{"queue" => "mail", "moved" => 6}} = rename(port, "emails", "mail")

      # One record, on the disk before the response; the archive untouched.
      assert lines(Store.log_path(dir)) ==
               log_before ++ [%{"rename" => "emails", "to" => "mail", "next_id" => 8}]

      assert File.read!(Store.archive_path(dir)) == archive_before

      for n <- 1..6 do
        assert {200, %{"queue" => "mail"}} = decoded(Queue.get(ref, "j_#{n}"))
      end

      assert {200, %{"queue" => "other"}} = decoded(Queue.get(ref, "j_7"))
      {200, %{"queues" => after_rename}} = decoded(Queue.queues(ref))
      assert Enum.find(after_rename, &(&1["name"] == "mail")) == %{emails_row | "name" => "mail"}
      refute Enum.any?(after_rename, &(&1["name"] == "emails"))

      assert {200, %{"jobs" => [%{"id" => "j_6"}]}} =
               Api.request(port, "x", "GET", "/jobs?queue=mail&key=k6")

      assert {200, %{"jobs" => []}} = Api.request(port, "x", "GET", "/jobs?queue=emails&key=k6")
      assert {200, %{"jobs" => jobs}} = Api.request(port, "x", "GET", "/jobs?queue=mail")
      assert Enum.map(jobs, & &1["id"]) == ~w(j_2 j_3 j_4 j_5 j_6)
      assert {200, %{"id" => "j_1"}} = create(ref, "mail", "k1")
      assert {200, %{"id" => "j_7"}} = create(ref, "other", "k1")

      # The lease in flight: same worker, same lease_until, and its ack works.
      assert {200, got} = decoded(Queue.get(ref, "j_4"))

      assert Map.take(got, ["worker", "lease_until"]) ==
               Map.take(leased, ["worker", "lease_until"])

      assert {204, nil} = Api.request(port, "w", "POST", "/queues/emails/lease")

      assert {200, %{"id" => "j_6", "queue" => "mail"}} =
               Api.request(port, "v", "POST", "/queues/mail/lease")

      assert {200, %{"state" => "done", "queue" => "mail"}} =
               Api.request(port, "w", "POST", "/jobs/j_4/ack")

      # Renamed back, everything is where it was, keys included.
      assert {200, %{"queue" => "emails", "moved" => 6}} = rename(port, "mail", "emails")
      assert {200, %{"id" => "j_1", "queue" => "emails"}} = create(ref, "emails", "k1")
      assert {200, %{"id" => "j_6"}} = create(ref, "emails", "k6")
      assert {200, %{"queues" => rows}} = decoded(Queue.queues(ref))
      assert Enum.map(rows, & &1["name"]) == ~w(emails other)
      assert :ok = Never.check(dir)
    end

    test "a name once freed is used again, as a fresh queue with free keys" do
      %{ref: ref, port: port} = start([])
      create(ref, "emails", "k")

      assert {200, %{"moved" => 1}} = rename(port, "emails", "mail")
      assert {404, _} = rename(port, "emails", "mail")
      assert {201, %{"id" => "j_2", "queue" => "emails"}} = create(ref, "emails", "k")
      assert {200, %{"id" => "j_1"}} = create(ref, "mail", "k")
      assert {409, %{"error" => "exists"}} = rename(port, "mail", "emails")
      assert {200, %{"queue" => "emails"}} = decoded(Queue.get(ref, "j_2"))
    end

    test "404 on an empty queue, 409 on a target with any job or on itself, 400 on a bad name" do
      %{ref: ref, port: port, clock: clock} = start([])
      create(ref, "emails", nil)
      create(ref, "done", nil, max_tries: 1)
      {200, _} = decoded(Queue.lease(ref, "done", 1_000, "w"))
      {200, _} = decoded(Queue.ack(ref, "j_2", "w"))
      Clock.advance(clock, @retain)
      {200, %{"archived" => 1, "done" => 0}} = decoded(Queue.health(ref))

      assert {404, _} = rename(port, "nobody", "mail")
      assert {409, %{"error" => "exists"}} = rename(port, "emails", "done")
      assert {409, %{"error" => "exists"}} = rename(port, "emails", "emails")
      # A queue whose only job is archived is still a queue to rename.
      assert {200, %{"queue" => "finished", "moved" => 1}} = rename(port, "done", "finished")
      assert {200, %{"queue" => "finished"}} = decoded(Queue.get(ref, "j_2"))

      assert {400, _} = rename(port, "emails", "no spaces")
      assert {400, _} = rename(port, "emails", String.duplicate("q", 65))
      assert {400, _} = rename(port, "bad%20name", "mail")

      assert {400, %{"error" => "'to' is required"}} =
               Api.request(port, "x", "POST", "/queues/emails/rename", "{}")

      assert {400, _} = Api.request(port, "x", "POST", "/queues/emails/rename", ~s({"to":1}))
      assert {405, _} = Api.request(port, "x", "GET", "/queues/emails/rename")
      assert {401, _} = Api.request(port, "", "POST", "/queues/emails/rename", ~s({"to":"m"}))
      assert {200, %{"queue" => "emails"}} = decoded(Queue.get(ref, "j_1"))
    end

    test "a rename whose write fails is a 503 and moves nothing, on the board or the disk" do
      # Batches: the create, then the rename.
      %{ref: ref, port: port, dir: dir, pid: pid, clock: clock} =
        start(fault: fn batch -> batch == 2 end)

      create(ref, "emails", "k")
      assert {503, _} = rename(port, "emails", "mail")
      assert {200, %{"queue" => "emails"}} = settled_get(ref, "j_1")
      assert {200, %{"id" => "j_1"}} = create(ref, "emails", "k")
      refute Enum.any?(lines(Store.log_path(dir)), &Map.has_key?(&1, "rename"))

      # The next one goes through.
      assert {200, %{"moved" => 1}} = rename(port, "emails", "mail")
      Service.stop(pid)
      %{ref: ref} = start(dir: dir, clock: clock)
      assert {200, %{"queue" => "mail"}} = decoded(Queue.get(ref, "j_1"))
    end

    test "a rename is a write the chaos switch counts, and the board comes back with it" do
      %{ref: ref} = start(crash: fn write -> write == 2 end, max_restarts: 5)
      create(ref, "emails", "k")
      assert {:error, :store} = decoded(Queue.rename(ref, "emails", "mail"))
      assert {200, %{"restarts" => 1}} = wait_health(ref)
      assert {200, %{"queue" => "mail"}} = decoded(Queue.get(ref, "j_1"))
      assert {200, %{"id" => "j_1"}} = create(ref, "mail", "k")
    end
  end

  describe "the rename on the disk" do
    test "the replay applies a rename in order: before it moves, after it stays" do
      dir = Service.tmp_dir()

      write(Store.log_path(dir), [
        job(1, key: "k"),
        job(2),
        %{job(3) | queue: "other"},
        {:obj, [{"rename", "emails"}, {"to", "mail"}]},
        job(4, key: "k")
      ])

      assert {:ok, %{jobs: jobs, next: 5}} = Store.open(dir)
      assert names(jobs) == %{1 => "mail", 2 => "mail", 3 => "other", 4 => "emails"}
    end

    test "a record after the rename that names the new queue keeps it" do
      dir = Service.tmp_dir()

      write(Store.log_path(dir), [
        job(1, key: "k"),
        {:obj, [{"rename", "emails"}, {"to", "mail"}]},
        %{
          job(1, key: "k", state: :leased, tries: 1, worker: "w", lease_until: 9)
          | queue: "mail"
        },
        job(2, key: "k")
      ])

      assert {:ok, %{jobs: jobs}} = Store.open(dir)
      assert jobs[1].queue == "mail"
      assert jobs[1].worker == "w"
      assert jobs[2].queue == "emails"
    end

    test "an archived job's queue: the log's renames on the archive's name, and only those after it left" do
      %{ref: ref, dir: dir, pid: pid, clock: clock} = start([])
      # j_1 archived in a, before the log's renames.
      create(ref, "a", "k", max_tries: 1)
      finish(ref, "a", "j_1")
      Clock.advance(clock, @retain)
      {200, %{"archived" => 1}} = decoded(Queue.health(ref))

      {200, _} = decoded(Queue.rename(ref, "a", "b"))
      # j_2 is created in a after the rename, and archived as a.
      create(ref, "a", "k", max_tries: 1)
      finish(ref, "a", "j_2")
      Clock.advance(clock, @retain)
      {200, %{"archived" => 2}} = decoded(Queue.health(ref))

      assert [%{"queue" => "a"}, %{"queue" => "a"}] = lines(Store.archive_path(dir))
      Service.stop(pid)

      assert {:ok, %{archived: archived}} = Store.open(dir)
      assert archived[1].queue == "b"
      assert archived[2].queue == "a"

      %{ref: ref, pid: pid} = start(dir: dir, clock: clock)
      assert {200, %{"id" => "j_1"}} = create(ref, "b", "k")
      assert {200, %{"id" => "j_2"}} = create(ref, "a", "k")
      assert {200, _} = decoded(Queue.rename(ref, "a", "c"))
      Service.stop(pid)

      assert {:ok, %{archived: archived}} = Store.open(dir)
      assert archived[1].queue == "b"
      assert archived[2].queue == "c"
    end

    test "compact folds two renames and an old archive name into the records, and a kill between its two rewrites changes nothing" do
      %{ref: ref, dir: dir, pid: pid, clock: clock} = start([])
      # j_1 archived in a, j_2 archived in b; then b -> c and a -> b, so the
      # archive's "b" means c and its "a" means b.
      create(ref, "a", "k", max_tries: 1)
      finish(ref, "a", "j_1")
      create(ref, "b", "k", max_tries: 1)
      finish(ref, "b", "j_2")
      Clock.advance(clock, @retain)
      {200, %{"archived" => 2}} = decoded(Queue.health(ref))
      create(ref, "live", "k")
      {200, _} = decoded(Queue.rename(ref, "b", "c"))
      {200, _} = decoded(Queue.rename(ref, "a", "b"))
      {200, _} = decoded(Queue.rename(ref, "live", "b-live"))
      Service.stop(pid)

      {:ok, before} = Store.open(dir)
      assert names(before.archived) == %{1 => "b", 2 => "c"}
      assert names(before.jobs) == %{3 => "b-live"}

      # A kill between the rewrites: the new log beside the old archive.
      copy = Service.tmp_dir()
      File.cp!(Store.log_path(dir), Store.log_path(copy))
      File.cp!(Store.archive_path(dir), Store.archive_path(copy))
      old_archive = File.read!(Store.archive_path(dir))

      assert {:ok, 1} = Store.compact(dir)
      log = lines(Store.log_path(dir))
      refute Enum.any?(log, &Map.has_key?(&1, "rename"))
      assert Enum.filter(log, &Map.has_key?(&1, "state")) |> Enum.map(& &1["queue"]) == ["b-live"]
      assert lines(Store.archive_path(dir)) |> Enum.map(& &1["queue"]) == ["b", "c"]
      assert {:ok, ^before} = Store.open(dir)

      File.cp!(Store.log_path(dir), Store.log_path(copy))
      File.write!(Store.archive_path(copy), old_archive)
      assert {:ok, ^before} = Store.open(copy)

      # A second compaction, and a start, keep it all.
      assert {:ok, 1} = Store.compact(dir)
      assert {:ok, ^before} = Store.open(dir)
      assert {:ok, 1} = Store.compact(copy)
      assert {:ok, ^before} = Store.open(copy)
      %{ref: ref} = start(dir: dir, clock: clock)
      assert {200, %{"id" => "j_1"}} = create(ref, "b", "k")
      assert {200, %{"id" => "j_2"}} = create(ref, "c", "k")
      assert {200, %{"id" => "j_3"}} = create(ref, "b-live", "k")
      assert {201, _} = create(ref, "a", "k")
    end

    test "verify refuses a bad rename record, and counts with renames applied" do
      dir = Service.tmp_dir()
      write(Store.log_path(dir), [job(1), {:obj, [{"rename", "emails"}, {"to", "mail"}]}, job(2)])

      assert {0, output} = run_cli(["verify", dir])
      assert output =~ "2 jobs: queued 2"
      assert {:ok, 2} = Store.compact(dir)
      assert [%{"queue" => "mail"}, %{"queue" => "emails"}] = lines(Store.log_path(dir))

      for {bad, rule} <- [
            {{:obj, [{"rename", "emails"}, {"to", "no spaces"}]}, "a rename's to"},
            {{:obj, [{"rename", ""}, {"to", "mail"}]}, "a rename's rename"},
            {{:obj, [{"rename", "emails"}, {"to", "emails"}]}, "two different queues"},
            {{:obj, [{"rename", "mail"}, {"to", "emails"}]}, "target has no job"},
            {{:obj, [{"id", "j_9"}, {"archived", true}, {"queue", "a b"}]}, "queue must be"}
          ] do
        bad_dir = Service.tmp_dir()
        write(Store.log_path(bad_dir), [job(1), %{job(2) | queue: "mail"}, bad])

        assert {1, output} = run_cli(["verify", bad_dir])
        assert output =~ rule
        assert {1, _} = run_cli(["compact", bad_dir])
      end
    end

    test "a kill anywhere in a load with a rename leaves every job moved or none, keys once per queue, one worker a job" do
      %{ref: ref, dir: dir} = start(sweep_ms: 5)
      for n <- 1..40, do: create(ref, "emails", "k#{n}")

      load =
        for w <- 1..6 do
          Task.async(fn -> work(ref, "w#{w}", 60) end)
        end

      Process.sleep(20)
      assert {200, %{"moved" => moved}} = decoded(Queue.rename(ref, "emails", "mail"))
      assert moved >= 40
      kill(ref, :store)
      Enum.each(load, &Task.await(&1, 60_000))
      wait_health(ref)

      bytes = File.read!(Store.log_path(dir))

      [{rename_at, rename_len}] =
        Regex.run(~r/\{"rename":"emails","to":"mail","next_id":\d+\}\n/, bytes, return: :index)

      assert :ok = Never.check(dir)

      cuts =
        [
          0,
          rename_at,
          rename_at + 1,
          rename_at + rename_len - 1,
          rename_at + rename_len,
          byte_size(bytes)
        ] ++
          Enum.map(1..30, fn _ -> :rand.uniform(byte_size(bytes)) end)

      for cut <- cuts do
        cut_dir = Service.tmp_dir()
        File.write!(Store.log_path(cut_dir), binary_part(bytes, 0, cut))
        # `open` itself refuses a key that names two jobs of a queue.
        assert {:ok, %{jobs: jobs}} = Store.open(cut_dir)
        whole = cut >= rename_at + rename_len
        prefix = binary_part(bytes, 0, cut)

        created_before =
          bytes
          |> binary_part(0, min(cut, rename_at))
          |> String.split("\n")
          |> Enum.drop(-1)
          |> Enum.flat_map(fn line ->
            case JSON.decode!(line) do
              %{"id" => id, "state" => _} -> [elem(Job.parse_id(id), 1)]
              _ -> []
            end
          end)
          |> Enum.uniq()

        for n <- created_before, Map.has_key?(jobs, n) do
          assert jobs[n].queue == if(whole, do: "mail", else: "emails"),
                 "cut #{cut}: j_#{n} in #{jobs[n].queue}"
        end

        for {_n, job} <- jobs do
          assert job.queue in ["emails", "mail"]
          assert job.state != :leased or is_binary(job.worker)
        end

        if String.ends_with?(prefix, "\n"), do: assert(:ok = Never.check(cut_dir))
      end
    end
  end

  # Helpers

  # A worker's loop: lease from either name, hand off to a friend, ack or fail,
  # and create with a key, taking whatever the queue says. Creates go to the
  # old name only, so the new one is empty until the rename fills it.
  defp work(ref, name, rounds) do
    for round <- 1..rounds do
      case Queue.lease(ref, Enum.random(["emails", "mail"]), 5_000, name) do
        {200, body} -> hand_on(ref, field(body, "id"), name, round)
        _other -> :ok
      end

      Queue.create(ref, "emails", "p", 3, 0, 0, "#{name}-#{rem(round, 7)}")
    end
  end

  defp hand_on(ref, id, name, round) do
    friend = name <> "-friend"

    case Queue.handoff(ref, id, name, friend) do
      {200, _} -> ack_or_fail(ref, id, friend, round)
      _other -> ack_or_fail(ref, id, name, round)
    end
  end

  defp ack_or_fail(ref, id, worker, round) do
    if rem(round, 3) == 0,
      do: Queue.fail(ref, id, worker, nil),
      else: Queue.ack(ref, id, worker)
  end

  defp field({:obj, pairs}, name), do: pairs |> List.keyfind(name, 0) |> elem(1)

  defp finish(ref, queue, id) do
    {200, %{"id" => ^id}} = decoded(Queue.lease(ref, queue, 1_000, "w"))
    {200, _} = decoded(Queue.ack(ref, id, "w"))
  end

  defp names(jobs), do: Map.new(jobs, fn {n, job} -> {n, job.queue} end)

  defp handoff(port, token, id, to),
    do: handoff_body(port, token, id, Json.encode({:obj, [{"to", to}]}) |> IO.iodata_to_binary())

  defp handoff_body(port, token, id, body),
    do: Api.request(port, token, "POST", "/jobs/#{id}/handoff", body)

  defp rename(port, from, to) do
    body = Json.encode({:obj, [{"to", to}]}) |> IO.iodata_to_binary()
    Api.request(port, "operator", "POST", "/queues/#{from}/rename", body)
  end

  defp create(ref, queue, key, opts \\ []) do
    ref
    |> Queue.create(
      queue,
      "p",
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

  defp start(opts), do: Service.start([retain_ms: @retain, sweep_ms: 3_600_000] ++ opts)

  defp kill(ref, name) do
    case Jobq.Registry.whereis(ref, name) do
      nil -> :ok
      pid -> Process.exit(pid, :kill)
    end
  end

  defp settled_get(ref, id, tries \\ 200) do
    case decoded(Queue.get(ref, id)) do
      {:error, :store} when tries > 0 ->
        Process.sleep(10)
        settled_get(ref, id, tries - 1)

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

  defp run_cli(argv) do
    {{status, stdout}, stderr} =
      with_io(:stderr, fn -> with_io(fn -> CLI.run(argv) end) end)

    {status, stdout <> stderr}
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
      worker: Keyword.get(fields, :worker),
      lease_until: Keyword.get(fields, :lease_until),
      archived_at: Keyword.get(fields, :archived_at),
      created_at: 1_789_000_000_000,
      updated_at: Keyword.get(fields, :updated_at, 1_789_000_000_000)
    }
  end
end
