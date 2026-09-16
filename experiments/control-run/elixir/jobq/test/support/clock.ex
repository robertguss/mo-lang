defmodule Jobq.Test.Clock do
  @moduledoc "A clock a test moves by hand, shared with the service's processes."

  @opaque t :: :counters.counters_ref()

  @doc "A clock standing at `now` milliseconds."
  @spec new(integer()) :: t()
  def new(now) do
    ref = :counters.new(1, [:atomics])
    :counters.add(ref, 1, now)
    ref
  end

  @doc "The zero-arity function the service reads the clock through."
  @spec reader(t()) :: Jobq.Clock.t()
  def reader(ref), do: fn -> :counters.get(ref, 1) end

  @doc "Move the clock forward."
  @spec advance(t(), non_neg_integer()) :: :ok
  def advance(ref, ms), do: :counters.add(ref, 1, ms)

  @doc "What the clock says now."
  @spec now(t()) :: integer()
  def now(ref), do: :counters.get(ref, 1)
end
