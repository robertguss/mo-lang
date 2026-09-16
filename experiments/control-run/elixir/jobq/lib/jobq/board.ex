defmodule Jobq.Board do
  @moduledoc """
  The board: the store and the queue, which restart together, within a budget.

  A failure of either is a failure of the board, not of one request: the
  process that holds the log's writes or the one that holds the jobs has died,
  a rule inside the service was found broken, or the chaos switch fired. Both
  are started again, `:one_for_all`, and the queue reads its jobs back off the
  log, so the board after a restart is the board the log holds. Restarting only
  the queue would leave the old store with commits the new queue never saw, and
  restarting only the store would leave the queue ahead of a log that lost its
  buffer, which is why it is both or neither.

  The budget is the supervisor's own intensity: `max_restarts` restarts inside
  `restart_window` seconds, and the next failure inside the window stops the
  board instead. `Jobq.Server` stops when the board does, and `jobq serve`
  exits 70.

  The restarts and the writes the board has applied are kept in a `:counters`
  array the service creates, so they outlive the processes they count.
  """

  use Supervisor

  @type counters :: :counters.counters_ref()

  # The array's slots.
  @writes 1
  @starts 2

  @doc "A fresh array for one service's counts."
  @spec counters() :: counters()
  def counters, do: :counters.new(2, [:write_concurrency])

  @doc "Count one start of the board; every start after the first is a restart."
  @spec started(counters()) :: :ok
  def started(counters), do: :counters.add(counters, @starts, 1)

  @doc "The restarts since the service started."
  @spec restarts(counters()) :: non_neg_integer()
  def restarts(counters), do: max(:counters.get(counters, @starts) - 1, 0)

  @doc "Count `count` writes applied, and return the total before and after."
  @spec applied(counters(), non_neg_integer()) :: {non_neg_integer(), non_neg_integer()}
  def applied(counters, count) do
    before = :counters.get(counters, @writes)
    :counters.add(counters, @writes, count)
    {before, before + count}
  end

  @doc """
  Start the board. Options: `:ref`, `:counters`, `:max_restarts`,
  `:restart_window`, and the store's and the queue's own.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    ref = Keyword.fetch!(opts, :ref)
    Supervisor.start_link(__MODULE__, opts, name: Jobq.Registry.via(ref, :board))
  end

  @impl Supervisor
  def init(opts) do
    children = [
      {Jobq.Store, Keyword.fetch!(opts, :store)},
      {Jobq.Queue, Keyword.fetch!(opts, :queue)}
    ]

    Supervisor.init(children,
      strategy: :one_for_all,
      max_restarts: Keyword.get(opts, :max_restarts, 5),
      max_seconds: Keyword.get(opts, :restart_window, 60)
    )
  end
end
