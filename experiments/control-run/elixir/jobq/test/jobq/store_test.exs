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
      record(1, state: :leased, attempts: 1),
      tombstone(2)
    ])

    assert {:ok, {jobs, _next}} = Store.read(dir)
    assert Map.keys(jobs) == [1]
    assert %Job{state: :leased, attempts: 1} = jobs[1]
  end

  test "a torn last line is dropped, everything before it is kept", %{dir: dir} do
    write(dir, [record(1, state: :queued)])
    File.write!(Store.log_path(dir), ~s({"id":"j_2","queue":"ema), [:append])

    assert {:ok, {jobs, _next}} = Store.read(dir)
    assert Map.keys(jobs) == [1]
  end

  test "a complete line that is not a record is a corrupt log", %{dir: dir} do
    write(dir, [record(1, state: :queued)])
    File.write!(Store.log_path(dir), ~s({"id":"j_2","half":true}\n), [:append])

    assert {:error, {:corrupt, 2}} = Store.read(dir)
  end

  test "compact leaves one line per live job, by id", %{dir: dir} do
    write(dir, [
      record(2, state: :queued),
      record(1, state: :queued),
      record(1, state: :done),
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

  test "a write that fails takes the store down and tells its waiters", %{dir: dir} do
    ref = make_ref()
    {:ok, pid} = Store.start_link(ref: ref, dir: dir, fault: fn batch -> batch == 1 end)
    Process.unlink(pid)
    monitor = Process.monitor(pid)
    tag = make_ref()

    Store.commit(ref, [{:put, job(1)}], {self(), tag}, {201, nil})

    assert_receive {^tag, {:error, :store}}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:write, _path, :injected}}, 1_000
    assert File.read!(Store.log_path(dir)) == ""
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
      max_attempts: 3,
      attempts: Keyword.get(fields, :attempts, 0),
      state: Keyword.get(fields, :state, :queued),
      created_at: 1_789_000_000_000,
      updated_at: 1_789_000_000_000
    }
  end

  defp tombstone(n), do: {:obj, [{"id", "j_" <> Integer.to_string(n)}, {"deleted", true}]}
end
