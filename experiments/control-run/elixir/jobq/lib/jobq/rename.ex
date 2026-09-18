defmodule Jobq.Rename do
  @moduledoc """
  A queue renamed, as a pure step over the jobs and the key map.

      requires  `from` has a job in some state, live or archived; `to` has
                none; `to` is not `from`
      ensures   every job that was in `from` is in `to`, and no other job
                moved; every key `{from, k}` is `{to, k}`, naming the same job,
                and no key names `from`; leases, tries, and states untouched

  The key map needs no clash check: a key names a job, live or archived, and
  `to` has none, so no `{to, k}` is in the map before the step. That is what
  the `requires` on `to` buys, and why a rename never lets a key name two jobs
  in one queue.

  A rename is one record on the log, `{"rename": from, "to": to, "next_id":
  n}`, where `n` is the id the service would give the next job it created:
  the rename moves the jobs below `n` that are in `from` at that point of the
  replay, and a job created after it (at `n` or above) into `from` is in a
  fresh queue of that name. `apply_name/4` is the step one job's queue name
  takes, and what the store runs over an archived job's name for every rename
  the log carries after the job left it. A record the change-5 program wrote
  has no `next_id`; the store reads it as the counter at that point of the
  replay, which is every job the folder had then.
  """

  alias Jobq.Job

  @type jobs :: %{pos_integer() => Job.t()}
  @type keys :: %{{String.t(), String.t()} => pos_integer()}

  @doc "Whether `from` may be renamed to `to`, given the jobs live and archived."
  @spec check([jobs()], String.t(), String.t()) :: :ok | :not_found | :exists
  def check(boards, from, to) do
    cond do
      not any_in?(boards, from) -> :not_found
      from == to or any_in?(boards, to) -> :exists
      true -> :ok
    end
  end

  defp any_in?(boards, queue),
    do: Enum.any?(boards, fn jobs -> Enum.any?(jobs, fn {_n, job} -> job.queue == queue end) end)

  @doc """
  The jobs with every one of `from` below `next_id` moved to `to`, and how
  many moved. The service's own jobs are all below its counter.
  """
  @spec jobs(jobs(), String.t(), String.t(), pos_integer()) :: {jobs(), non_neg_integer()}
  def jobs(jobs, from, to, next_id) do
    Enum.reduce(jobs, {jobs, 0}, fn
      {n, %Job{queue: ^from} = job}, {acc, moved} when n < next_id ->
        {Map.put(acc, n, %{job | queue: to}), moved + 1}

      _other, acc ->
        acc
    end)
  end

  @doc "The key map with every key of `from` a key of `to`."
  @spec keys(keys(), String.t(), String.t()) :: keys()
  def keys(keys, from, to) do
    Map.new(keys, fn
      {{^from, key}, n} -> {{to, key}, n}
      other -> other
    end)
  end

  @typedoc "One rename as the replay holds it: `from`, `to`, and its `next_id`."
  @type t :: {String.t(), String.t(), pos_integer()}

  @doc "The queue name of job `n` after one rename."
  @spec apply_name(String.t(), pos_integer(), t()) :: String.t()
  def apply_name(from, n, {from, to, next_id}) when n < next_id, do: to
  def apply_name(name, _n, _rename), do: name

  @doc "The queue name of job `n` after a list of renames, in order."
  @spec apply_all(String.t(), pos_integer(), [t()]) :: String.t()
  def apply_all(name, n, renames),
    do: Enum.reduce(renames, name, fn rename, name -> apply_name(name, n, rename) end)

  @doc """
  The rule a rename record on the disk breaks, or `:ok`: both names keep the
  queue name's rule, they differ, and a `next_id`, when the record has one, is
  an id counter of at least 1.
  """
  @spec check_record(map()) :: :ok | {:error, String.t()}
  def check_record(%{} = map) do
    with :ok <- name(map, "rename"),
         :ok <- name(map, "to"),
         :ok <- next_id(map),
         :ok <- only(map) do
      if map["rename"] == map["to"],
        do: {:error, "a rename names two different queues"},
        else: :ok
    end
  end

  defp name(map, field) do
    case Job.queue(Map.get(map, field)) do
      {:ok, _name} -> :ok
      {:error, message} -> {:error, "a rename's #{field}: #{message}"}
    end
  end

  defp next_id(%{"next_id" => n}) when is_integer(n) and n >= 1, do: :ok

  defp next_id(%{"next_id" => _n}),
    do: {:error, "a rename's next_id is a whole number of at least 1"}

  defp next_id(_map), do: :ok

  defp only(map) do
    case Map.keys(map) -- ["rename", "to", "next_id"] do
      [] -> :ok
      [field | _rest] -> {:error, "a rename has no #{field}"}
    end
  end
end
