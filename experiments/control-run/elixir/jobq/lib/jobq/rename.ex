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

  A rename is one record on the log, `{"rename": from, "to": to}`, and the
  replay applies it in order: `apply_name/3` is the step one job's queue name
  takes, and what the store runs over an archived job's name for every rename
  the log carries after the job left it.
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

  @doc "The jobs with every one of `from` moved to `to`, and how many moved."
  @spec jobs(jobs(), String.t(), String.t()) :: {jobs(), non_neg_integer()}
  def jobs(jobs, from, to) do
    Enum.reduce(jobs, {jobs, 0}, fn
      {n, %Job{queue: ^from} = job}, {acc, moved} ->
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

  @doc "A queue name after one rename."
  @spec apply_name(String.t(), String.t(), String.t()) :: String.t()
  def apply_name(from, from, to), do: to
  def apply_name(name, _from, _to), do: name

  @doc "A queue name after a list of renames, in order."
  @spec apply_all(String.t(), [{String.t(), String.t()}]) :: String.t()
  def apply_all(name, renames),
    do: Enum.reduce(renames, name, fn {from, to}, name -> apply_name(name, from, to) end)

  @doc """
  The rule a rename record on the disk breaks, or `:ok`: both names keep the
  queue name's rule, and they differ.
  """
  @spec check_record(map()) :: :ok | {:error, String.t()}
  def check_record(%{} = map) do
    with :ok <- name(map, "rename"),
         :ok <- name(map, "to"),
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

  defp only(map) do
    case Map.keys(map) -- ["rename", "to"] do
      [] -> :ok
      [field | _rest] -> {:error, "a rename has no #{field}"}
    end
  end
end
