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
    test "a created job is queued with no attempts", %{ref: ref} do
      assert {201, {:obj, fields}} = Queue.create(ref, "emails", "hi", 3)
      assert {"id", "j_1"} in fields
      assert {"state", "queued"} in fields
      assert {"attempts", 0} in fields
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
    test "a lease hands out the oldest queued job of its queue and counts the attempt", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "one", 3)
      assert {201, _job} = Queue.create(ref, "other", "two", 3)
      assert {201, _job} = Queue.create(ref, "emails", "three", 3)

      assert {200, job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert id(job) == "j_1"
      assert field(job, "state") == "leased"
      assert field(job, "attempts") == 1
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

    test "a fail before the last attempt queues the job again, with its reason", %{ref: ref} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 2)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {200, job} = Queue.fail(ref, "j_1", "bob", "boom")
      assert field(job, "state") == "queued"
      assert field(job, "attempts") == 1
      assert field(job, "reason") == "boom"

      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
      assert {200, dead} = Queue.fail(ref, "j_1", "bob", "boom again")
      assert field(dead, "state") == "dead"
      assert field(dead, "attempts") == 2
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
      assert field(job, "attempts") == 1
    end
  end

  describe "a lease is a deadline, not a timer" do
    test "a lease that runs out is queued again, with its attempts kept", %{ref: ref, clock: clock} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 3)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")

      Clock.advance(clock, 1_001)

      assert {200, job} = Queue.lease(ref, "emails", 1_000, "alice")
      assert id(job) == "j_1"
      assert field(job, "attempts") == 2
      assert field(job, "worker") == "alice"
    end

    test "a lease that runs out on the last attempt is dead", %{ref: ref, clock: clock} do
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

    test "a lease that ran out with nobody asking is freed on the idle look", %{ref: ref, clock: clock, dir: dir} do
      assert {201, _job} = Queue.create(ref, "emails", "hi", 3)
      assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")

      Clock.advance(clock, 1_001)

      # Only the idle look can have written a queued record with one attempt on
      # it: nothing else has asked the service anything since the lease.
      assert eventually(fn ->
               dir
               |> Jobq.Store.log_path()
               |> File.read!()
               |> String.split("\n", trim: true)
               |> Enum.map(&JSON.decode!/1)
               |> Enum.any?(fn record ->
                 record["state"] == "queued" and record["attempts"] == 1
               end)
             end)

      assert {200, %{"queued" => 1, "leased" => 0}} = health(ref)
    end
  end

  describe "health" do
    test "counts the states and an uptime that grows with the clock", %{ref: ref, clock: clock} do
      assert {200, %{"queued" => 0, "leased" => 0, "done" => 0, "dead" => 0, "uptime_ms" => 0}} =
               health(ref)

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
    for _n <- 1..3, do: Queue.lease(ref, "emails", 1_000, "bob")
    Queue.ack(ref, "j_1", "bob")
    Queue.fail(ref, "j_2", "bob", "boom")
    Clock.advance(clock, 1_001)
    Queue.lease(ref, "emails", 1_000, "alice")
    Queue.delete(ref, "j_5")

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
