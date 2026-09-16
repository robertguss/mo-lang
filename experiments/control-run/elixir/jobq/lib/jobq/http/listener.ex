defmodule Jobq.Http.Listener do
  @moduledoc """
  The listener: the socket, the connections' supervisor, and a pool of
  acceptors, in that order under `:rest_for_one`, so a socket that is lost
  takes its acceptors with it and they come back with the new one.
  """

  use Supervisor

  @acceptors 10

  @doc """
  Start the listener. Options: `:ref`, `:port`, and the connection's
  `:idle_ms`, `:request_ms`, `:max_body`, `:acceptors`.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    ref = Keyword.fetch!(opts, :ref)
    Supervisor.start_link(__MODULE__, opts, name: Jobq.Registry.via(ref, :listener))
  end

  @impl Supervisor
  def init(opts) do
    ref = Keyword.fetch!(opts, :ref)

    conn_opts = %{
      ref: ref,
      idle_ms: Keyword.get(opts, :idle_ms, 10_000),
      request_ms: Keyword.get(opts, :request_ms, 10_000),
      max_body: Keyword.get(opts, :max_body, 131_072)
    }

    acceptors =
      for id <- 1..Keyword.get(opts, :acceptors, @acceptors) do
        Supervisor.child_spec({Jobq.Http.Acceptor, ref: ref, id: id, conn_opts: conn_opts},
          id: {Jobq.Http.Acceptor, id}
        )
      end

    children =
      [
        {Jobq.Http.Socket, ref: ref, port: Keyword.fetch!(opts, :port)},
        {Task.Supervisor, name: Jobq.Registry.via(ref, :conns)}
      ] ++ acceptors

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
