defmodule Jobq.Test.Never do
  @moduledoc """
  The `never`s, read off the store's log.

  The log is the durable order of everything the service did, so the claims
  that matter can be checked against it after a run rather than guessed at
  from the inside: a job is never leased while it is already leased (which is
  what "never held by two workers" comes to on one service), a job's `tries`
  never exceed its `max_tries` and only grow by one at a lease, a scheduled job
  is never leased and never queued before its `run_at`, a done job never moves
  again, and a dead job moves only to the `queued` of a retry, with its `tries`
  back at 0.

  Change 5 moved the first of them rather than dropped it: a leased record
  after a leased one is a handoff, and is one only when the worker changed and
  the `tries` and the `lease_until` did not, so the job still has one worker at
  every line. A rename record names no job and moves no state.

  A log may carry lines the version before this change wrote, so a record's
  count of tries is read under either name.
  """

  @doc """
  Check every record in `dir`'s log in order. Returns `:ok` or
  `{:error, line_number, message}`.
  """
  @spec check(Path.t()) :: :ok | {:error, pos_integer(), String.t()}
  def check(dir) do
    dir
    |> Jobq.Store.log_path()
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{}}, fn {line, number}, {:ok, seen} ->
      case step(JSON.decode!(line), seen) do
        {:ok, seen} -> {:cont, {:ok, seen}}
        {:error, message} -> {:halt, {:error, number, message}}
      end
    end)
    |> case do
      {:ok, _seen} -> :ok
      other -> other
    end
  end

  defp step(%{"id" => id, "deleted" => true}, seen), do: {:ok, Map.put(seen, id, :deleted)}
  defp step(%{"next" => _n}, seen), do: {:ok, seen}
  defp step(%{"rename" => _from, "to" => _to}, seen), do: {:ok, seen}

  # A job that left the board for the archive never moves on the board again.
  defp step(%{"id" => id, "archived" => true}, seen), do: {:ok, Map.put(seen, id, :archived)}

  defp step(record, seen) do
    %{"id" => id} = record

    case fault(record, Map.get(seen, id)) do
      nil -> {:ok, Map.put(seen, id, remember(record))}
      message -> {:error, "#{id}: #{message}"}
    end
  end

  defp remember(record) do
    %{
      state: record["state"],
      tries: tries(record),
      run_at: record["run_at"],
      worker: record["worker"],
      lease_until: record["lease_until"],
      updated_at: record["updated_at"]
    }
  end

  # `tries` under the name the record was written with.
  defp tries(record), do: record["tries"] || record["attempts"]
  defp max_tries(record), do: record["max_tries"] || record["max_attempts"]

  defp fault(record, previous) do
    %{"state" => state} = record
    tries = tries(record)
    max = max_tries(record)

    cond do
      tries > max -> "tries #{tries} over max_tries #{max}"
      state == "leased" -> lease_fault(record, tries, previous)
      state == "queued" -> queued_fault(record, previous)
      state_of(previous) == "done" -> "left done for #{state}"
      state_of(previous) == "dead" -> "left dead for #{state}"
      previous == :archived -> "came back from the archive as #{state}"
      true -> nil
    end
  end

  defp lease_fault(record, tries, previous) do
    cond do
      state_of(previous) == "leased" -> handoff_fault(record, tries, previous)
      state_of(previous) == "scheduled" -> "leased while scheduled"
      state_of(previous) in ["done", "dead"] -> "leased while #{state_of(previous)}"
      is_map(previous) and tries != previous.tries + 1 -> "leased with tries #{tries}"
      true -> nil
    end
  end

  # A handoff: another worker, the same lease, the same tries.
  defp handoff_fault(record, tries, previous) do
    cond do
      record["worker"] == previous.worker -> "leased while already leased"
      tries != previous.tries -> "handed off with tries #{tries}, was #{previous.tries}"
      record["lease_until"] != previous.lease_until -> "handed off with a new lease_until"
      true -> nil
    end
  end

  # A scheduled job is queued only once its `run_at` has been reached; a dead
  # job is queued only by a retry, which puts its tries back to 0.
  defp queued_fault(record, previous) do
    cond do
      state_of(previous) == "scheduled" and record["updated_at"] < previous.run_at ->
        "queued at #{record["updated_at"]}, before its run_at #{previous.run_at}"

      state_of(previous) == "dead" and tries(record) != 0 ->
        "retried with tries #{tries(record)}"

      state_of(previous) == "done" ->
        "left done for queued"

      true ->
        nil
    end
  end

  defp state_of(%{state: state}), do: state
  defp state_of(_previous), do: nil
end
