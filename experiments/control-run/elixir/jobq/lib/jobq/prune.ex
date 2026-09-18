defmodule Jobq.Prune do
  @moduledoc """
  The archive pruned, as a pure step over the archived jobs and the key map.

      requires  the age is at least 1,000 ms, so the cutoff `now - age` is
                behind every job archived in the last second
      ensures   no live job is touched (the step never sees one); every job
                removed has `archived_at` at or before the cutoff, and every
                job kept has one after it; every key a removed job held is
                free, and every other key names what it named before

  A prune is one record on the log, `{"prune": cutoff, "count": k}`, never one
  per job. The replay applies it to the archived jobs the log had sent off
  before it (`Jobq.Store`), which is why the record carries the cutoff rather
  than the age: a replay on another day reaches the same jobs.
  """

  alias Jobq.Job

  @type archived :: %{pos_integer() => Job.t()}
  @type keys :: %{{String.t(), String.t()} => pos_integer()}

  @doc "The cutoff a prune of `older_than_ms` at `now` removes up to, inclusive."
  @spec cutoff(integer(), pos_integer()) :: integer()
  def cutoff(now, older_than_ms)
      when is_integer(now) and is_integer(older_than_ms) and older_than_ms >= 1_000,
      do: now - older_than_ms

  @doc """
  The archive and the key map with every job archived at or before `cutoff`
  removed, and the jobs removed.
  """
  @spec step(archived(), keys(), integer()) :: {archived(), keys(), [Job.t()]}
  def step(archived, keys, cutoff) do
    {gone, kept} = Enum.split_with(archived, fn {_n, job} -> due?(job, cutoff) end)
    gone = Enum.map(gone, fn {_n, job} -> job end)
    {Map.new(kept), Enum.reduce(gone, keys, &free/2), gone}
  end

  @doc "Whether an archived job is gone under `cutoff`."
  @spec due?(Job.t(), integer()) :: boolean()
  def due?(%Job{archived_at: at}, cutoff), do: is_integer(at) and at <= cutoff

  # A key is freed only when it names the job that goes: a key of the queue
  # that a later job holds is that job's.
  defp free(%Job{key: nil}, keys), do: keys

  defp free(%Job{n: n} = job, keys) do
    case Map.fetch(keys, {job.queue, job.key}) do
      {:ok, ^n} -> Map.delete(keys, {job.queue, job.key})
      _other -> keys
    end
  end

  @doc """
  The rule a prune record on the disk breaks, or `:ok`: an integer cutoff of
  at least 0, a count of at least 1, and no other field.
  """
  @spec check_record(map()) :: :ok | {:error, String.t()}
  def check_record(%{} = map) do
    cond do
      not (is_integer(map["prune"]) and map["prune"] >= 0) ->
        {:error, "a prune's cutoff is a whole number of milliseconds"}

      not (is_integer(map["count"]) and map["count"] >= 1) ->
        {:error, "a prune's count is a whole number of at least 1"}

      (extra = Map.keys(map) -- ["prune", "count"]) != [] ->
        {:error, "a prune has no #{hd(extra)}"}

      true ->
        :ok
    end
  end
end
