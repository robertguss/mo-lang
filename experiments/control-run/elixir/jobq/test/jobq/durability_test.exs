defmodule Jobq.DurabilityTest do
  use ExUnit.Case, async: true

  alias Jobq.Queue
  alias Jobq.Store
  alias Jobq.Test.Clock
  alias Jobq.Test.Never
  alias Jobq.Test.Service

  test "the record is on the disk before the response comes back" do
    %{ref: ref, dir: dir} = Service.start()

    assert {201, _job} = Queue.create(ref, "emails", "hi", 3)
    assert [record] = records(dir)
    assert record["id"] == "j_1"

    assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
    assert [_created, leased] = records(dir)
    assert leased["state"] == "leased"

    assert {200, _job} = Queue.ack(ref, "j_1", "bob")
    assert [_created, _leased, done] = records(dir)
    assert done["state"] == "done"

    assert {204, nil} = Queue.delete(ref, "j_1")
    assert [_created, _leased, _done, tombstone] = records(dir)
    assert tombstone == %{"id" => "j_1", "deleted" => true}
  end

  test "a job is never lost: what was created and not deleted comes back with its last state" do
    %{ref: ref, dir: dir, pid: pid, clock: clock} = Service.start()

    for n <- 1..10, do: Queue.create(ref, "emails", "payload #{n}", 2)
    assert {200, _job} = Queue.lease(ref, "emails", 60_000, "bob")
    assert {200, _job} = Queue.ack(ref, "j_1", "bob")
    assert {200, _job} = Queue.lease(ref, "emails", 60_000, "bob")
    assert {200, _job} = Queue.fail(ref, "j_2", "bob", "boom")
    assert {204, nil} = Queue.delete(ref, "j_3")

    before = states(ref)
    Service.stop(pid)

    %{ref: ref} = Service.start(dir: dir, clock: clock)
    assert states(ref) == before
    assert map_size(before) == 9
    assert before["j_1"] == "done"
    assert before["j_2"] == "queued"
    refute Map.has_key?(before, "j_3")
  end

  test "a job that was leased when the service stopped is queued, or dead, at its next look" do
    %{ref: ref, dir: dir, pid: pid, clock: clock} = Service.start()

    assert {201, _job} = Queue.create(ref, "emails", "twice", 3)
    assert {201, _job} = Queue.create(ref, "emails", "once", 1)
    assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
    assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
    assert states(ref) == %{"j_1" => "leased", "j_2" => "leased"}

    Service.stop(pid)
    Clock.advance(clock, 1_001)
    %{ref: ref} = Service.start(dir: dir, clock: clock)

    assert {200, job} = Queue.get(ref, "j_1")
    assert state_of(job) == "queued"
    assert {200, dead} = Queue.get(ref, "j_2")
    assert state_of(dead) == "dead"
    assert :ok = Never.check(dir)
  end

  test "a scheduled job comes back scheduled, and is queued once its run_at passes" do
    %{ref: ref, dir: dir, pid: pid, clock: clock} = Service.start()

    assert {201, _job} = Queue.create(ref, "emails", "delayed", 3, 60_000, 0)
    assert {201, _job} = Queue.create(ref, "emails", "backoff", 3, 0, 30_000)
    assert {200, _job} = Queue.lease(ref, "emails", 1_000, "bob")
    assert {200, _job} = Queue.fail(ref, "j_2", "bob", "boom")
    assert states(ref) == %{"j_1" => "scheduled", "j_2" => "scheduled"}

    Service.stop(pid)
    %{ref: ref} = Service.start(dir: dir, clock: clock)

    assert states(ref) == %{"j_1" => "scheduled", "j_2" => "scheduled"}
    assert {204, nil} = Queue.lease(ref, "emails", 1_000, "alice")

    Clock.advance(clock, 30_000)
    assert {200, job} = Queue.lease(ref, "emails", 1_000, "alice")
    assert id_of(job) == "j_2"
    assert field(job, "tries") == 2
    assert {204, nil} = Queue.lease(ref, "emails", 1_000, "alice")

    Clock.advance(clock, 30_000)
    assert {200, delayed} = Queue.lease(ref, "emails", 1_000, "alice")
    assert id_of(delayed) == "j_1"
    assert field(delayed, "tries") == 1
    assert :ok = Never.check(dir)
  end

  test "a lease that had not run out is still held after a restart" do
    %{ref: ref, dir: dir, pid: pid, clock: clock} = Service.start()

    assert {201, _job} = Queue.create(ref, "emails", "hi", 3)
    assert {200, _job} = Queue.lease(ref, "emails", 60_000, "bob")
    Service.stop(pid)

    %{ref: ref} = Service.start(dir: dir, clock: clock)
    assert {200, job} = Queue.get(ref, "j_1")
    assert state_of(job) == "leased"
    assert {204, nil} = Queue.lease(ref, "emails", 1_000, "alice")
    assert {200, _job} = Queue.ack(ref, "j_1", "bob")
  end

  test "ids do not go back over a restart" do
    %{ref: ref, dir: dir, pid: pid, clock: clock} = Service.start()

    for _n <- 1..3, do: Queue.create(ref, "emails", "hi", 1)
    assert {204, nil} = Queue.delete(ref, "j_3")
    Service.stop(pid)

    %{ref: ref} = Service.start(dir: dir, clock: clock)
    assert {201, job} = Queue.create(ref, "emails", "hi", 1)
    assert id_of(job) == "j_4"
  end

  test "compact keeps the state and the ids, and replays to the same jobs" do
    %{ref: ref, dir: dir, pid: pid, clock: clock} = Service.start()

    for n <- 1..20, do: Queue.create(ref, "emails", "payload #{n}", 2)
    for _n <- 1..5, do: Queue.lease(ref, "emails", 60_000, "bob")
    assert {200, _job} = Queue.ack(ref, "j_1", "bob")
    assert {204, nil} = Queue.delete(ref, "j_20")
    before = states(ref)
    Service.stop(pid)

    lines_before = dir |> Store.log_path() |> File.read!() |> String.split("\n", trim: true)
    assert {:ok, 19} = Store.compact(dir)
    lines_after = dir |> Store.log_path() |> File.read!() |> String.split("\n", trim: true)
    # 19 live jobs and the line that keeps the counter above the deleted j_20.
    assert length(lines_after) == 20
    assert length(lines_before) > length(lines_after)

    %{ref: ref} = Service.start(dir: dir, clock: clock)
    assert states(ref) == before
  end

  describe "under faults" do
    test "every answer is right or a 503, the store keeps its word, and the work finishes" do
      # The tenth and the fortieth write of the run fail, counted across the
      # store's restarts. A write that fails takes the store down; the tree
      # brings the queue back on the log, which is the state the disk agrees
      # with, and the callers of that batch are told 503.
      writes = :counters.new(1, [])

      fault = fn _batch ->
        :counters.add(writes, 1, 1)
        :counters.get(writes, 1) in [10, 40]
      end

      %{ref: ref, dir: dir, clock: clock} = Service.start(fault: fault)

      answers =
        for round <- 1..100 do
          # A third of the jobs carry a backoff, so a fail or a lease that runs
          # out under the faults goes through `scheduled` rather than straight
          # back to `queued`; every fifth job has one try only, so some of them
          # reach `dead` and there is something for a retry to take.
          backoff = if rem(round, 3) == 0, do: 1_000, else: 0
          max_tries = if rem(round, 5) == 0, do: 1, else: 3

          {created, tries} =
            attempt(fn ->
              Queue.create(ref, "emails", "payload #{round}", max_tries, 0, backoff)
            end)
          {leased, more} = attempt(fn -> Queue.lease(ref, "emails", 60_000, "bob") end)
          {_finished, last} = attempt(fn -> finish(ref, leased, round) end)
          tries ++ more ++ [created, leased] ++ last
        end
        |> List.flatten()

      assert Enum.all?(answers, fn {status, _body} ->
               status in [200, 201, 204, 409] or status == :error
             end)

      assert Enum.any?(answers, &match?({:error, :store}, &1))
      assert :ok = Never.check(dir)
      assert :counters.get(writes, 1) > 40

      # With the faults behind it, and the leases and backoffs of the run given
      # their time, a worker takes everything that is left to done or dead.
      Clock.advance(clock, 60_001)
      drain(ref)

      states = states(ref)
      counts = states |> Map.values() |> Enum.frequencies()
      assert Map.get(counts, "queued", 0) == 0
      assert Map.get(counts, "scheduled", 0) == 0
      assert Map.get(counts, "leased", 0) == 0
      assert Map.get(counts, "done", 0) + Map.get(counts, "dead", 0) == map_size(states)
      assert map_size(states) > 90
      assert :ok = Never.check(dir)

      # And an operator retries the dead ones, which go round again and end
      # done or dead once more, with nothing left queued or scheduled.
      dead = for {id, "dead"} <- states, do: id
      assert dead != []
      Enum.each(dead, fn id -> attempt(fn -> Queue.retry(ref, id) end) end)
      Clock.advance(clock, 60_001)
      drain(ref)

      after_retry = states(ref) |> Map.values() |> Enum.frequencies()
      assert Map.get(after_retry, "queued", 0) == 0
      assert Map.get(after_retry, "scheduled", 0) == 0
      assert Map.get(after_retry, "leased", 0) == 0
      assert :ok = Never.check(dir)
    end
  end

  # A client that is told 503 tries again, as a producer or a worker would.
  defp attempt(fun, tries \\ 100, seen \\ [])

  defp attempt(fun, tries, seen) do
    case fun.() do
      {:error, :store} = answer when tries > 0 ->
        Process.sleep(5)
        attempt(fun, tries - 1, [answer | seen])

      answer ->
        {answer, seen}
    end
  end

  defp finish(ref, {200, job}, round) do
    if rem(round, 3) == 0,
      do: Queue.fail(ref, id_of(job), "bob", "boom"),
      else: Queue.ack(ref, id_of(job), "bob")
  end

  defp finish(_ref, other, _round), do: other

  defp drain(ref, rounds \\ 400)
  defp drain(_ref, 0), do: :ok

  defp drain(ref, rounds) do
    case Queue.lease(ref, "emails", 60_000, "bob") do
      {200, job} ->
        Queue.ack(ref, id_of(job), "bob")
        drain(ref, rounds - 1)

      _other ->
        :ok
    end
  end

  defp field({:obj, fields}, name) do
    {_name, value} = Enum.find(fields, fn {key, _value} -> key == name end) || {name, nil}
    value
  end

  defp records(dir) do
    dir
    |> Store.log_path()
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
  end

  defp states(ref) do
    {200, {:obj, [{"jobs", jobs}]}} = Queue.list(ref, nil, nil)
    Map.new(jobs, fn job -> {id_of(job), state_of(job)} end)
  end

  defp id_of(job), do: field(job, "id")
  defp state_of(job), do: field(job, "state")
end
