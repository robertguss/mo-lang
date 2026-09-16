defmodule Jobq.Server do
  @moduledoc """
  One service: the store, the queue, and the listener, under `:rest_for_one`.

  The order is the order of the dependencies. A store that stops because a
  write failed takes the queue with it, and the queue comes back by replaying
  the log, which is the state the disk agrees with; a queue that crashes takes
  the listener with it, so no connection is left holding a request against a
  process that is gone. Nothing below a crash outlives it, and nothing above it
  is disturbed.
  """

  use Supervisor

  alias Jobq.Http.Socket

  @type ref :: term()

  @doc """
  Start a service.

  Options: `:ref` (default `:default`), `:dir`, `:port` (default 7900, 0 asks
  the kernel for a free one), `:clock`, `:sweep_ms`, `:fault`, and the
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

    children = [
      {Jobq.Store, ref: ref, dir: dir, fault: Keyword.get(opts, :fault, fn _batch -> false end)},
      {Jobq.Queue,
       ref: ref,
       dir: dir,
       clock: Keyword.get(opts, :clock, Jobq.Clock.system()),
       sweep_ms: Keyword.get(opts, :sweep_ms, 100)},
      {Jobq.Http.Listener,
       ref: ref,
       port: Keyword.get(opts, :port, 7900),
       idle_ms: Keyword.get(opts, :idle_ms, 10_000),
       request_ms: Keyword.get(opts, :request_ms, 10_000),
       acceptors: Keyword.get(opts, :acceptors, 10)}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
