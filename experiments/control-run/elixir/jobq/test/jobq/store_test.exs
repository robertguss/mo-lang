defmodule Jobq.StoreTest do
  use ExUnit.Case, async: true

  alias Jobq.Job
  alias Jobq.Store
  alias Jobq.Test.Service

  setup do
    %{dir: Service.tmp_dir()}
  end

  test "a directory with no log replays to no jobs", %{dir: dir} do
    assert {:ok, {jobs, _next}} = Store.read(dir)
    assert jobs == %{}
  end

  test "the last record of an id wins, and a tombstone removes it", %{dir: dir} do
    write(dir, [
      record(1, state: :queued),
      record(2, state: :queued),
      record(1, state: :leased, tries: 1, worker: "bob", lease_until: 1_789_000_060_000),
      tombstone(2)
    ])

    assert {:ok, {jobs, _next}} = Store.read(dir)
    assert Map.keys(jobs) == [1]
    assert %Job{state: :leased, tries: 1} = jobs[1]
  end

  test "a torn last line is dropped, everything before it is kept", %{dir: dir} do
    write(dir, [record(1, state: :queued)])
    File.write!(Store.log_path(dir), ~s({"id":"j_2","queue":"ema), [:append])

    assert {:ok, {jobs, _next}} = Store.read(dir)
    assert Map.keys(jobs) == [1]
  end

  test "a complete line that is not JSON at all is a corrupt log", %{dir: dir} do
    write(dir, [record(1, state: :queued)])
    File.write!(Store.log_path(dir), "not json\n", [:append])

    assert {:error, {:corrupt, 2}} = Store.read(dir)
  end

  test "a record that is not a job names its key and the rule it breaks", %{dir: dir} do
    write(dir, [record(1, state: :queued)])
    File.write!(Store.log_path(dir), ~s({"id":"j_2","half":true}\n), [:append])

    assert {:error, {:record, "j_2", "'state' is required"}} = Store.read(dir)
  end

  test "a record in a state its fields do not fit refuses the folder", %{dir: dir} do
    write(dir, [
      record(1, state: :queued),
      %{
        "id" => "j_2",
        "queue" => "emails",
        "state" => "leased",
        "payload" => "hi",
        "tries" => 1,
        "max_tries" => 3,
        "backoff_ms" => 0,
        "created_at" => 1_789_000_000_000,
        "updated_at" => 1_789_000_000_000
      }
    ])

    assert {:error, {:record, "j_2", "a leased job has a worker and a lease_until"}} =
             Store.read(dir)

    assert {:error, {:record, "j_2", _rule}} = Store.compact(dir)
  end

  test "a counter below an id the log carries refuses the folder", %{dir: dir} do
    write(dir, [{:obj, [{"next", 1}]}, record(1, state: :queued)])
    assert {:error, {:corrupt, 1}} = Store.read(dir)
  end

  test "a job created after a compaction's counter starts at it, and the folder opens", %{
    dir: dir
  } do
    write(dir, [record(1, state: :queued), record(2, state: :queued), tombstone(2)])
    assert {:ok, 1} = Store.compact(dir)
    write(dir, [record(3, state: :queued)])
    assert {:ok, {jobs, 4}} = Store.read(dir)
    assert Map.keys(jobs) == [1, 3]

    write(dir, [{:obj, [{"next", 3}]}])
    assert {:error, {:corrupt, 4}} = Store.read(dir)
  end

  test "a counter that is not a number refuses the folder", %{dir: dir} do
    write(dir, [record(1, state: :queued), {:obj, [{"next", "soon"}]}])
    assert {:error, {:corrupt, 2}} = Store.read(dir)
  end

  test "compact leaves one line per live job, by id", %{dir: dir} do
    write(dir, [
      record(2, state: :queued),
      record(1, state: :queued),
      record(1, state: :done, tries: 1),
      record(3, state: :queued),
      tombstone(3)
    ])

    assert {:ok, 2} = Store.compact(dir)

    ids =
      dir
      |> Store.log_path()
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)
      |> Enum.map(& &1["id"])
      |> Enum.reject(&is_nil/1)

    assert ids == ["j_1", "j_2"]
    assert String.contains?(File.read!(Store.log_path(dir)), ~s({"next":4}))
    assert {:ok, {jobs, _next}} = Store.read(dir)
    assert jobs[1].state == :done
  end

  test "compact on a directory with no log writes an empty one", %{dir: dir} do
    assert {:ok, 0} = Store.compact(dir)
    assert File.read!(Store.log_path(dir)) == ""
  end

  test "the counter the next id comes from never goes back", %{dir: dir} do
    write(dir, [record(1, state: :queued), record(2, state: :queued), tombstone(2)])
    assert {:ok, {jobs, 3}} = Store.read(dir)
    assert Map.keys(jobs) == [1]

    assert {:ok, 1} = Store.compact(dir)
    assert {:ok, {jobs, 3}} = Store.read(dir)
    assert Map.keys(jobs) == [1]

    write(dir, [{:obj, [{"next", 9}]}])
    assert {:ok, {_jobs, 9}} = Store.read(dir)
  end

  test "a write that fails tells its waiters, keeps the store, and moves the epoch", %{dir: dir} do
    ref = make_ref()
    {:ok, pid} = Store.start_link(ref: ref, dir: dir, fault: fn batch -> batch == 1 end)
    monitor = Process.monitor(pid)
    tag = make_ref()

    assert Store.epoch(ref) == 0
    Store.commit(ref, [{:put, job(1)}], {self(), tag}, {201, nil}, 0)

    assert_receive {^tag, {:error, :store}}, 1_000
    refute_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 200
    assert File.read!(Store.log_path(dir)) == ""
    assert Store.epoch(ref) == 1

    # The next write, under the epoch the store is in now, goes through on its
    # own; one still tagged with the epoch the failure left is refused.
    stale = make_ref()
    Store.commit(ref, [{:put, job(2)}], {self(), stale}, {201, nil}, 0)
    assert_receive {^stale, {:error, :store}}, 1_000

    fresh = make_ref()
    Store.commit(ref, [{:put, job(2)}], {self(), fresh}, {201, nil}, 1)
    assert_receive {^fresh, {201, nil}}, 1_000
    assert File.read!(Store.log_path(dir)) =~ ~s("id":"j_2")

    Supervisor.stop(pid)
  end

  defp write(dir, records) do
    lines = Enum.map(records, fn record -> [Jobq.Json.encode(record), "\n"] end)
    File.write!(Store.log_path(dir), lines, [:append])
  end

  defp record(n, fields), do: n |> job(fields) |> Job.record()

  defp job(n, fields \\ []) do
    %Job{
      n: n,
      queue: "emails",
      payload: "hi",
      max_tries: 3,
      tries: Keyword.get(fields, :tries, 0),
      state: Keyword.get(fields, :state, :queued),
      worker: Keyword.get(fields, :worker),
      lease_until: Keyword.get(fields, :lease_until),
      created_at: 1_789_000_000_000,
      updated_at: 1_789_000_000_000
    }
  end

  defp tombstone(n), do: {:obj, [{"id", "j_" <> Integer.to_string(n)}, {"deleted", true}]}
end
