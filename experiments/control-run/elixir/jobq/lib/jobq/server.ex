defmodule Jobq.Server do
  @moduledoc """
  One service: the board (the store and the queue) and the listener.

  The two are apart on purpose. A board that fails restarts on its own, inside
  `Jobq.Board`, and the listener is not touched: the port stays bound, and a
  request that arrives while the board is rebuilding is answered `503` by the
  router, which finds no queue to ask. A listener that fails restarts on its
  own as well, and the board is not touched.

  The board is the service's one *significant* child: when it has used its
  restart budget and stops, the service stops with it, and `jobq serve` turns
  that into exit 70.
  """

  use Supervisor

  alias Jobq.Board
  alias Jobq.Http.Socket

  @type ref :: term()

  @doc """
  Start a service.

  Options: `:ref` (default `:default`), `:dir`, `:port` (default 7900, 0 asks
  the kernel for a free one), `:clock`, `:sweep_ms`, `:retain_ms`, `:fault`, the budget's
  `:max_restarts` (default 5) and `:restart_window` (seconds, default 60), the
  chaos switch `:crash_every` (default 0, never) or a test's `:crash`, and the
  listener's options.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    ref = Keyword.get(opts, :ref, :default)

    Supervisor.start_link(__MODULE__, Keyword.put(opts, :ref, ref),
      name: Jobq.Registry.via(ref, :server)
    )
  end

  @doc "The port the service listens on."
  @spec port(ref()) :: :inet.port_number()
  def port(ref), do: Socket.port(ref)

  @doc "Stop a service and everything under it."
  @spec stop(ref()) :: :ok
  def stop(ref) do
    case Jobq.Registry.whereis(ref, :server) do
      nil -> :ok
      pid -> Supervisor.stop(pid)
    end
  end

  @impl Supervisor
  def init(opts) do
    ref = Keyword.fetch!(opts, :ref)
    dir = Keyword.fetch!(opts, :dir)
    clock = Keyword.get(opts, :clock, Jobq.Clock.system())
    counters = Board.counters()

    board = [
      ref: ref,
      max_restarts: Keyword.get(opts, :max_restarts, 5),
      restart_window: Keyword.get(opts, :restart_window, 60),
      store: [
        ref: ref,
        dir: dir,
        counters: counters,
        fault: Keyword.get(opts, :fault, fn _batch -> false end),
        crash: Keyword.get_lazy(opts, :crash, fn -> crash_every(opts) end)
      ],
      queue: [
        ref: ref,
        dir: dir,
        clock: clock,
        counters: counters,
        # The uptime is the service's, so it is taken here, once, and a
        # restart of the board does not start it again.
        started_at: clock.(),
        sweep_ms: Keyword.get(opts, :sweep_ms, 100),
        retain_ms: Keyword.get(opts, :retain_ms, 86_400_000)
      ]
    ]

    children = [
      Supervisor.child_spec({Board, board}, restart: :transient, significant: true),
      {Jobq.Http.Listener,
       ref: ref,
       port: Keyword.get(opts, :port, 7900),
       idle_ms: Keyword.get(opts, :idle_ms, 10_000),
       request_ms: Keyword.get(opts, :request_ms, 10_000),
       acceptors: Keyword.get(opts, :acceptors, 10)}
    ]

    Supervisor.init(children, strategy: :one_for_one, auto_shutdown: :any_significant)
  end

  # The chaos switch: the N-th, 2N-th, ... write the board applies fails.
  defp crash_every(opts) do
    case Keyword.get(opts, :crash_every, 0) do
      0 -> fn _write -> false end
      every -> fn write -> rem(write, every) == 0 end
    end
  end
end
