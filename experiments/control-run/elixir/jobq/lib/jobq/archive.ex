defmodule Jobq.Archive do
  @moduledoc """
  The archive move, as a pure step: which job is due, and what a move writes.

  A done or dead job whose `updated_at` is `retain_ms` or more before now is
  due. Its move is two records, in the order the store writes them: the job
  with `archived_at` set, appended to the archive, and the log's word that the
  job left the board. `Jobq.Store` puts the first on the disk before the
  second, so a kill between them leaves the job in both files, which an open
  reads as archived.
  """

  alias Jobq.Job
  alias Jobq.Store

  @doc "Whether `job` is due for the archive at `now`, kept `retain_ms`."
  @spec due?(Job.t(), integer(), pos_integer()) :: boolean()
  def due?(%Job{state: state, updated_at: updated_at}, now, retain_ms),
    do: state in [:done, :dead] and updated_at <= now - retain_ms

  @doc "The job as archived at `now`, and the two records the move writes."
  @spec move(Job.t(), integer()) :: {Job.t(), [Store.record()]}
  def move(%Job{state: state} = job, now) when state in [:done, :dead] do
    archived = %{job | archived_at: now}
    {archived, [{:archive, archived}, {:archived, Job.id(job)}]}
  end
end
