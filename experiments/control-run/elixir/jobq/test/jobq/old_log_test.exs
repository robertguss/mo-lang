defmodule Jobq.OldLogTest do
  @moduledoc """
  A folder the version before this change served still opens.

  `test/fixtures/round7/data` was written by the round 7 escript, before the
  rename: `attempts` and `max_attempts`, no `backoff_ms`, no `run_at`, no
  `scheduled`. Its README says what stands in it. The tests here open it with
  the service as it is now, without a tool and without an error.
  """

  use ExUnit.Case, async: true

  alias Jobq.Queue
  alias Jobq.Store
  alias Jobq.Test.Never
  alias Jobq.Test.Service

  @fixture "test/fixtures/round7/data"

  # Well past the hour-long leases the fixture's two leased jobs were given.
  @after_the_leases 1_790_000_000_000

  # The fixture's jobs finished some five days before that; these tests are
  # about the old shape, not the archive, so nothing is archived under them.
  @retain_ms 2_678_400_000

  setup do
    dir = Service.tmp_dir()
    File.cp!(Store.log_path(@fixture), Store.log_path(dir))
    %{dir: dir}
  end

  test "every job is there with its state, by the new rules, at the first look", %{dir: dir} do
    %{ref: ref} = Service.start(dir: dir, clock_at: @after_the_leases, retain_ms: @retain_ms)

    # j_1's lease ran out with a try to spare, so it is queued again; j_5's ran
    # out on its last one, so it is dead. Neither has a backoff, so neither is
    # scheduled.
    assert states(ref) == %{
             "j_1" => "queued",
             "j_2" => "queued",
             "j_3" => "done",
             "j_4" => "dead",
             "j_5" => "dead"
           }

    assert {200, job} = Queue.get(ref, "j_1")
    assert field(job, "tries") == 1
    assert field(job, "max_tries") == 2
    assert field(job, "backoff_ms") == 0
    refute field(job, "worker")

    assert {200, dead} = Queue.get(ref, "j_4")
    assert field(dead, "tries") == 1
    assert field(dead, "max_tries") == 1
    assert field(dead, "reason") == "disk full"

    # The tombstone still removes j_6, and the counter is still above it.
    assert {404, _error} = Queue.get(ref, "j_6")
    assert {201, fresh} = Queue.create(ref, "emails", "after the change", 1)
    assert field(fresh, "id") == "j_7"
  end

  test "the service goes on from there: a lease, a retry, and a backoff", %{dir: dir} do
    %{ref: ref} = Service.start(dir: dir, clock_at: @after_the_leases, retain_ms: @retain_ms)

    assert {200, leased} = Queue.lease(ref, "emails", 60_000, "dave")
    assert field(leased, "id") == "j_1"
    assert field(leased, "tries") == 2
    assert {200, done} = Queue.ack(ref, "j_1", "dave")
    assert field(done, "state") == "done"

    # j_4 was dead in the old log; a retry is what change 1 adds for it.
    assert {200, retried} = Queue.retry(ref, "j_4")
    assert field(retried, "state") == "queued"
    assert field(retried, "tries") == 0
    refute field(retried, "reason")

    assert :ok = Never.check(dir)
  end

  test "from the first write on, only the new names are written", %{dir: dir} do
    %{ref: ref, pid: pid} =
      Service.start(dir: dir, clock_at: @after_the_leases, retain_ms: @retain_ms)

    assert {201, _job} = Queue.create(ref, "emails", "after the change", 3, 0, 5_000)
    Service.stop(pid)

    # The old lines are still in the log, untouched; everything the service
    # wrote itself is new.
    written = Enum.drop(lines(dir), 13)
    assert written != []
    assert Enum.all?(written, fn line -> not String.contains?(line, "attempts") end)
  end

  test "compact leaves a log with no old name in it", %{dir: dir} do
    %{ref: ref, pid: pid} =
      Service.start(dir: dir, clock_at: @after_the_leases, retain_ms: @retain_ms)

    before = states(ref)
    Service.stop(pid)

    assert {:ok, 5} = Store.compact(dir)
    log = File.read!(Store.log_path(dir))
    refute log =~ "attempts"
    refute log =~ "max_attempts"

    # Every line but the `{"next":N}` marker is a job.
    for line <- Enum.filter(lines(dir), &String.contains?(&1, ~s("id"))) do
      assert line =~ ~s("tries":)
      assert line =~ ~s("max_tries":)
      assert line =~ ~s("backoff_ms":)
    end

    %{ref: ref} = Service.start(dir: dir, clock_at: @after_the_leases, retain_ms: @retain_ms)
    assert states(ref) == before
  end

  test "a log written by hand in the old shape opens the same way" do
    dir = Service.tmp_dir()

    File.write!(Store.log_path(dir), """
    {"id":"j_1","queue":"emails","state":"queued","payload":"by hand","attempts":0,"max_attempts":3,"created_at":1789000000000,"updated_at":1789000000000}
    {"id":"j_2","queue":"emails","state":"leased","payload":"held","attempts":1,"max_attempts":1,"created_at":1789000000000,"updated_at":1789000000000,"worker":"bob","lease_until":1789000060000}
    {"id":"j_3","queue":"reports","state":"done","payload":"finished","attempts":2,"max_attempts":3,"created_at":1789000000000,"updated_at":1789000000000}
    """)

    %{ref: ref} = Service.start(dir: dir, clock_at: 1_789_000_060_001)

    assert states(ref) == %{"j_1" => "queued", "j_2" => "dead", "j_3" => "done"}
    assert {200, job} = Queue.get(ref, "j_3")
    assert field(job, "tries") == 2
    assert field(job, "max_tries") == 3
    assert field(job, "backoff_ms") == 0
  end

  defp lines(dir) do
    dir |> Store.log_path() |> File.read!() |> String.split("\n", trim: true)
  end

  defp states(ref) do
    {200, {:obj, [{"jobs", jobs}]}} = Queue.list(ref, nil, nil)
    Map.new(jobs, fn job -> {field(job, "id"), field(job, "state")} end)
  end

  defp field({:obj, fields}, name) do
    {_name, value} = Enum.find(fields, fn {key, _value} -> key == name end) || {name, nil}
    value
  end
end
