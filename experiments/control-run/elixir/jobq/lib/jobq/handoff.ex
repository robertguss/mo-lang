defmodule Jobq.Handoff do
  @moduledoc """
  A lease handed to another worker, as a pure step.

      requires  the job is leased, to the caller, on a lease that has not run
                out at this look (the look runs before the step, so a lease
                that ran out is no longer leased here)
      ensures   the job is leased to `to`, with the same `lease_until` and the
                same `tries`; only `worker` and `updated_at` differ, and a
                handoff to the caller itself changes nothing at all

  The lease moves; it is not copied. The job is one record under its id, and
  that record names one worker, so "a job is never held by two workers at
  once" holds at every look and in every record: the old worker is a stranger
  from the handoff's response on.
  """

  alias Jobq.Job

  @doc """
  The job handed from `caller` to `to` at `now`: `{:ok, job, changed?}`, or
  `:not_held` when the caller does not hold its lease.
  """
  @spec step(Job.t(), String.t(), String.t(), integer()) ::
          {:ok, Job.t(), boolean()} | :not_held
  def step(%Job{state: :leased, worker: caller} = job, caller, caller, _now),
    do: {:ok, job, false}

  def step(%Job{state: :leased, worker: caller} = job, caller, to, now),
    do: {:ok, %{job | worker: to, updated_at: now}, true}

  def step(%Job{}, _caller, _to, _now), do: :not_held
end
