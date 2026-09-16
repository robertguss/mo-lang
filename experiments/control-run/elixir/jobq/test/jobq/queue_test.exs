defmodule Jobq.QueueTest do
  use ExUnit.Case, async: true

  alias Jobq.Queue
  alias Jobq.Test.Clock
  alias Jobq.Test.Never
  alias Jobq.Test.Service

  setup do
    Service.start(sweep_ms: 50)
  end

  describe "create, read, list and delete" do
    test "a created job is queued with no tries", %{ref: ref} do
      assert {201, {:obj, fields}} = Queue.create(ref, "emails", "hi", 3)
      assert {"id", "j_1"} in fields
      assert {"state", "queued"} in fields
      assert {"tries", 0} in fields
      assert {200, {:obj, ^fields}} = Queue.get(ref, "j_1")
    end

    test "ids never repeat, and a job that is not there is 404", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "one", 3)
      assert {201, {:obj, fields}} = Queue.create(ref, "emails", "two", 3)
      assert {"id", "j_2"} in fields
      assert {404, _error} = Queue.get(ref, "j_9")
      assert {404, _error} = Queue.get(ref, "nonsense")
    end

    test "a listing filters by queue and by state, by id, at most 100", %{ref: ref} do
      for n <- 1..120, do: Queue.create(ref, "q#{rem(n, 2)}", "payload #{n}", 3)
      assert {200, {:obj, [{"jobs", all}]}} = Queue.list(ref, nil, nil)
      assert length(all) == 100
      assert ["j_1", "j_2", "j_3" | _rest] = Enum.map(all, &id/1)

      assert {200, {:obj, [{"jobs", odd}]}} = Queue.list(ref, "q1", nil)
      assert Enum.all?(odd, fn job -> field(job, "queue") == "q1" end)

      assert {200, _job} = Queue.lease(ref, "q1", 1_000, "bob")
      assert {200, {:obj, [{"jobs", leased}]}} = Queue.list(ref, nil, :leased)
      assert length(leased) == 1
    end

    test "delete takes a queued, done or dead job and refuses a leased one", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 3)
      assert {204, nil} = Queue.delete(ref, "j_1")
      assert {404, _error} = Queue.get(ref, "j_1")
      assert {404, _error} = Queue.delete(ref, "j_1")

      assert {201, _job} = Queue.create(ref, "emails", "hi", 3)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {409, _error} = Queue.delete(ref, "j_2")
      assert {200, _job} = Queue.ack(ref, "j_2", "bob")
      assert {204, nil} = Queue.delete(ref, "j_2")
    end
  end

  describe "lease, ack and fail" do
    test "a lease hands out the oldest queued job of its queue and counts the try", %{
      ref: ref
    } do
      assert {201, _job} = Queue.create(ref, "emails", "one", 3)
      assert {201, _job} = Queue.create(ref, "other", "two", 3)
      assert {201, _job} = Queue.create(ref, "emails", "three", 3)

      assert {200, job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert id(job) == "j_1"
      assert field(job, "state") == "leased"
      assert field(job, "tries") == 1
      assert field(job, "worker") == "bob"

      assert {200, next} = Queue.lease(ref, "emails", 1_000, "bob")
      assert id(next) == "j_3"
      assert {204, nil} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {204, nil} = Queue.lease(ref, "empty", 1_000, "bob")
    end

    test "an ack by the holder is done; by anyone else, 409", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 3)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {409, _error} = Queue.ack(ref, "j_1", "alice")
      assert {200, job} = Queue.ack(ref, "j_1", "bob")
      assert field(job, "state") == "done"
      assert {409, _error} = Queue.ack(ref, "j_1", "bob")
      assert {404, _error} = Queue.ack(ref, "j_7", "bob")
    end

    test "a fail before the last try queues the job again, with its reason", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 2)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {200, job} = Queue.fail(ref, "j_1", "bob", "boom")
      assert field(job, "state") == "queued"
      assert field(job, "tries") == 1
      assert field(job, "reason") == "boom"

      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {200, dead} = Queue.fail(ref, "j_1", "bob", "boom again")
      assert field(dead, "state") == "dead"
      assert field(dead, "tries") == 2
      assert {204, nil} = Queue.lease(ref, "emails", 1_000, "bob")
    end

    test "a done job is never leased again, and a dead job is never leased", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "done one", 1)
      assert {201, _job} = Queue.create(ref, "emails", "dead one", 1)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {200, _job} = Queue.ack(ref, "j_1", "bob")
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {200, dead} = Queue.fail(ref, "j_2", "bob", "boom")
      assert field(dead, "state") == "dead"
      assert {204, nil} = Queue.lease(ref, "emails", 1_000, "bob")
    end

    test "two workers race for one job and exactly one holds it", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 100)

      results =
        1..32
        |> Task.async_stream(fn n -> Queue.lease(ref, "emails", 60_000, "w#{n}") end,
          max_concurrency: 32,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, fn {status, _body} -> status == 200 end) == 1
      assert Enum.count(results, fn {status, _body} -> status == 204 end) == 31

      assert {200, job} = Queue.get(ref, "j_1")
      assert field(job, "tries") == 1
    end
  end

  describe "a lease is a deadline, not a timer" do
    test "a lease that runs out is queued again, with its tries kept", %{
      ref: ref,
      clock: clock
    } do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 3)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")

      Clock.advance(clock, 1_001)

      assert {200, job} = Queue.lease(ref, "emails", 1_000, "alice")
      assert id(job) == "j_1"
      assert field(job, "tries") == 2
      assert field(job, "worker") == "alice"
    end

    test "a lease that runs out on the last try is dead", %{ref: ref, clock: clock} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 1)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")

      Clock.advance(clock, 1_001)

      assert {200, job} = Queue.get(ref, "j_1")
      assert field(job, "state") == "dead"
      assert {204, nil} = Queue.lease(ref, "emails", 1_000, "alice")
    end

    test "a worker whose lease ran out and who acks anyway is told 409", %{ref: ref, clock: clock} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 3)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")

      Clock.advance(clock, 1_001)

      assert {200, job} = Queue.lease(ref, "emails", 1_000, "alice")
      assert field(job, "worker") == "alice"
      assert {409, _error} = Queue.ack(ref, "j_1", "bob")
      assert {200, _job} = Queue.ack(ref, "j_1", "alice")
    end

    test "a lease that ran out with nobody asking is freed on the idle look", %{
      ref: ref,
      clock: clock,
      dir: dir
    } do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 3)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")

      Clock.advance(clock, 1_001)

      # Only the idle look can have written a queued record with one try on
      # it: nothing else has asked the service anything since the lease.
      assert eventually(fn ->
               dir
               |> Jobq.Store.log_path()
               |> File.read!()
               |> String.split("\n", trim: true)
               |> Enum.map(&JSON.decode!/1)
               |> Enum.any?(fn record ->
                 record["state"] == "queued" and record["tries"] == 1
               end)
             end)

      assert {200, %{"queued" => 1, "leased" => 0}} = health(ref)
    end
  end

  describe "a delay, a backoff and a retry" do
    test "a job created with a delay waits in scheduled until its run_at", %{
      ref: ref,
      clock: clock
    } do
      now = Clock.now(clock)
      assert {201, job} = Queue.create(ref, "emails", "hi", 3, 1_000, 0)
      assert field(job, "state") == "scheduled"
      assert field(job, "run_at") == Jobq.Clock.iso8601(now + 1_000)
      assert {204, nil} = Queue.lease(ref, "emails", 1_000, "bob")

      Clock.advance(clock, 1_000)
      assert {200, leased} = Queue.lease(ref, "emails", 1_000, "bob")
      assert id(leased) == "j_1"
      assert field(leased, "state") == "leased"
      assert field(leased, "tries") == 1
      refute field(leased, "run_at")
    end

    test "a job that has come due takes its place in the queue by id", %{ref: ref, clock: clock} do
      assert {201, _job} = Queue.create(ref, "emails", "delayed", 3, 1_000, 0)
      assert {201, _job} = Queue.create(ref, "emails", "plain", 3)
      assert {200, first} = Queue.lease(ref, "emails", 1_000, "bob")
      assert id(first) == "j_2"

      Clock.advance(clock, 1_000)
      assert {200, second} = Queue.lease(ref, "emails", 1_000, "bob")
      assert id(second) == "j_1"
    end

    test "a fail with a backoff schedules the job at now + backoff_ms", %{
      ref: ref,
      clock: clock
    } do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 3, 0, 5_000)
      assert {200, _job} = Queue.lease(ref, "emails", 60_000, "bob")
      now = Clock.now(clock)

      assert {200, job} = Queue.fail(ref, "j_1", "bob", "boom")
      assert field(job, "state") == "scheduled"
      assert field(job, "tries") == 1
      assert field(job, "reason") == "boom"
      assert field(job, "run_at") == Jobq.Clock.iso8601(now + 5_000)
      assert {204, nil} = Queue.lease(ref, "emails", 1_000, "alice")

      Clock.advance(clock, 5_000)
      assert {200, leased} = Queue.lease(ref, "emails", 1_000, "alice")
      assert field(leased, "tries") == 2
    end

    test "a fail with a backoff on the last try is dead, not scheduled", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 1, 0, 5_000)
      assert {200, _job} = Queue.lease(ref, "emails", 60_000, "bob")
      assert {200, job} = Queue.fail(ref, "j_1", "bob", "boom")
      assert field(job, "state") == "dead"
      refute field(job, "run_at")
    end

    test "a lease that runs out is scheduled with a backoff and queued without", %{
      ref: ref,
      clock: clock
    } do
      assert {201, _job} = Queue.create(ref, "emails", "backoff", 3, 0, 5_000)
      assert {201, _job} = Queue.create(ref, "plain", "none", 3)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {200, _job} = Queue.lease(ref, "plain", 1_000, "bob")

      Clock.advance(clock, 1_001)

      assert {200, backed_off} = Queue.get(ref, "j_1")
      assert field(backed_off, "state") == "scheduled"
      assert field(backed_off, "tries") == 1
      assert {200, plain} = Queue.get(ref, "j_2")
      assert field(plain, "state") == "queued"
    end

    test "a retry puts a dead job back with its tries at 0 and its reason dropped", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 1, 0, 5_000)
      assert {200, _job} = Queue.lease(ref, "emails", 60_000, "bob")
      assert {200, dead} = Queue.fail(ref, "j_1", "bob", "boom")
      assert field(dead, "state") == "dead"

      assert {200, job} = Queue.retry(ref, "j_1")
      assert field(job, "state") == "queued"
      assert field(job, "tries") == 0
      assert field(job, "backoff_ms") == 5_000
      assert field(job, "max_tries") == 1
      refute field(job, "reason")
      refute field(job, "worker")

      assert {200, leased} = Queue.lease(ref, "emails", 60_000, "alice")
      assert id(leased) == "j_1"
      assert field(leased, "tries") == 1
    end

    test "a retry of a job that is not dead is 409, and of one that is not there 404", %{
      ref: ref,
      clock: clock
    } do
      assert {201, _job} = Queue.create(ref, "emails", "queued", 3)
      assert {201, _job} = Queue.create(ref, "emails", "leased", 3)
      assert {201, _job} = Queue.create(ref, "later", "scheduled", 3, 60_000, 0)
      assert {409, _error} = Queue.retry(ref, "j_1")

      assert {200, _job} = Queue.lease(ref, "emails", 60_000, "bob")
      assert {409, _error} = Queue.retry(ref, "j_1")
      assert {200, _job} = Queue.ack(ref, "j_1", "bob")
      assert {409, _error} = Queue.retry(ref, "j_1")
      assert {409, _error} = Queue.retry(ref, "j_3")
      assert {404, _error} = Queue.retry(ref, "j_9")
      assert {404, _error} = Queue.retry(ref, "nonsense")

      Clock.advance(clock, 60_000)
      assert {409, _error} = Queue.retry(ref, "j_3")
    end

    test "a scheduled job is listed, counted, and deleted like a queued one", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "soon", 3, 60_000, 0)
      assert {201, _job} = Queue.create(ref, "emails", "now", 3)

      assert {200, {:obj, [{"jobs", [job]}]}} = Queue.list(ref, nil, :scheduled)
      assert id(job) == "j_1"
      assert {200, %{"queued" => 1, "scheduled" => 1}} = health(ref)

      assert {204, nil} = Queue.delete(ref, "j_1")
      assert {404, _error} = Queue.get(ref, "j_1")
      assert {200, %{"scheduled" => 0}} = health(ref)
    end

    test "a run_at that passed with nobody asking is queued on the idle look", %{
      ref: ref,
      clock: clock,
      dir: dir
    } do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 3, 1_000, 0)
      Clock.advance(clock, 1_000)

      # Nothing has asked the service anything since the create, so only the
      # idle look can have written the queued record.
      assert eventually(fn ->
               dir
               |> Jobq.Store.log_path()
               |> File.read!()
               |> String.split("\n", trim: true)
               |> Enum.map(&JSON.decode!/1)
               |> Enum.any?(fn record ->
                 record["state"] == "queued" and record["id"] == "j_1"
               end)
             end)

      assert {200, %{"queued" => 1, "scheduled" => 0}} = health(ref)
    end
  end

  describe "health" do
    test "counts the states and an uptime that grows with the clock", %{ref: ref, clock: clock} do
      assert {200,
              %{
                "queued" => 0,
                "scheduled" => 0,
                "leased" => 0,
                "done" => 0,
                "dead" => 0,
                "uptime_ms" => 0
              }} = health(ref)

      assert {201, _job} = Queue.create(ref, "emails", "hi", 1)
      assert {201, _job} = Queue.create(ref, "emails", "hi", 1)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {200, _job} = Queue.ack(ref, "j_1", "bob")
      Clock.advance(clock, 5)

      assert {200, %{"queued" => 1, "done" => 1, "uptime_ms" => 5}} = health(ref)
    end
  end

  test "the log keeps every never the transitions can break", %{ref: ref, dir: dir, clock: clock} do
    for n <- 1..5, do: Queue.create(ref, "emails", "payload #{n}", 2)
    for n <- 6..8, do: Queue.create(ref, "emails", "payload #{n}", 1, 500, 2_000)
    for _n <- 1..3, do: Queue.lease(ref, "emails", 1_000, "bob")
    Queue.ack(ref, "j_1", "bob")
    Queue.fail(ref, "j_2", "bob", "boom")
    Clock.advance(clock, 1_001)
    Queue.lease(ref, "emails", 1_000, "alice")
    Queue.delete(ref, "j_5")

    # The delayed jobs are due now; each takes its one try, dies, and is
    # retried, so the log carries a scheduled, a dead and a retry as well.
    for _n <- 1..3, do: Queue.lease(ref, "emails", 1_000, "carol")
    Queue.fail(ref, "j_6", "carol", "boom")
    Clock.advance(clock, 1_001)
    Queue.lease(ref, "emails", 1_000, "carol")
    Queue.retry(ref, "j_6")

    assert :ok = Never.check(dir)
  end

  defp health(ref) do
    {status, {:obj, fields}} = Queue.health(ref)
    {status, Map.new(fields)}
  end

  defp field({:obj, fields}, name) do
    {_name, value} = Enum.find(fields, fn {key, _value} -> key == name end) || {name, nil}
    value
  end

  defp id(job), do: field(job, "id")

  defp eventually(check, tries \\ 100) do
    cond do
      check.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(check, tries - 1)
    end
  end
end
