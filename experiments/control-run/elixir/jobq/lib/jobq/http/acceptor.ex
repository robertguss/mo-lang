defmodule Jobq.Http.Acceptor do
  @moduledoc """
  One acceptor of the pool: accept a connection, hand it to a process of its
  own under the connection supervisor, accept the next one.

  The accepted socket is passive, so nothing can be delivered to the acceptor's
  mailbox between the accept and the handover; a connection that says nothing
  costs one sleeping process and no room in anybody's mailbox, which is why
  1,200 silent connections do not keep a producer waiting.
  """

  use GenServer, restart: :permanent

  alias Jobq.Http.Conn
  alias Jobq.Http.Socket

  require Logger

  @accept_timeout 1_000

  @doc "Start an acceptor. Options: `:ref`, `:id`, and the connection's `:opts`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl GenServer
  def init(opts) do
    {:ok, Map.new(opts), {:continue, :accept}}
  end

  @impl GenServer
  def handle_continue(:accept, state) do
    socket = Socket.socket(state.ref)

    case :gen_tcp.accept(socket, @accept_timeout) do
      {:ok, client} ->
        hand_over(client, state)
        {:noreply, state, {:continue, :accept}}

      {:error, :timeout} ->
        {:noreply, state, {:continue, :accept}}

      {:error, :closed} ->
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.warning("jobq: accept failed: #{inspect(reason)}")
        {:noreply, state, {:continue, :accept}}
    end
  end

  defp hand_over(client, state) do
    conns = Jobq.Registry.via(state.ref, :conns)

    case Task.Supervisor.start_child(conns, Conn, :serve, [client, state.conn_opts]) do
      {:ok, pid} ->
        case :gen_tcp.controlling_process(client, pid) do
          :ok -> send(pid, :handover)
          {:error, _reason} -> :gen_tcp.close(client)
        end

      {:error, reason} ->
        Logger.warning("jobq: no process for a connection: #{inspect(reason)}")
        :gen_tcp.close(client)
    end
  end
end
