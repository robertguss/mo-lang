defmodule Jobq.Test.Never do
  @moduledoc """
  The `never`s, read off the store's log.

  The log is the durable order of everything the service did, so the claims
  that matter can be checked against it after a run rather than guessed at
  from the inside: a job is never leased while it is already leased (which is
  what "never held by two workers" comes to on one service), a job's attempts
  never exceed its `max_attempts` and only grow by one at a lease, and a job
  that is done or dead never moves again except to be deleted.
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

  defp step(record, seen) do
    %{"id" => id, "state" => state, "attempts" => attempts} = record

    case fault(record, Map.get(seen, id)) do
      nil -> {:ok, Map.put(seen, id, %{state: state, attempts: attempts})}
      message -> {:error, "#{id}: #{message}"}
    end
  end

  defp fault(record, previous) do
    %{"state" => state, "attempts" => attempts, "max_attempts" => max} = record

    cond do
      attempts > max ->
        "attempts #{attempts} over max_attempts #{max}"

      state == "leased" ->
        lease_fault(attempts, previous)

      state_of(previous) in ["done", "dead"] ->
        "left #{state_of(previous)} for #{state}"

      true ->
        nil
    end
  end

  defp lease_fault(attempts, previous) do
    cond do
      state_of(previous) == "leased" -> "leased while already leased"
      is_map(previous) and attempts != previous.attempts + 1 -> "leased with attempts #{attempts}"
      true -> nil
    end
  end

  defp state_of(%{state: state}), do: state
  defp state_of(_previous), do: nil
end
