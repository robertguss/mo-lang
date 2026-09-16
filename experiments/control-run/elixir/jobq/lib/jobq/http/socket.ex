defmodule Jobq.Http.Socket do
  @moduledoc """
  The process that owns the listening socket.

  It is its own process so the acceptors can crash and be restarted without
  the socket closing under them, and so `jobq check`, which asks the kernel for
  a free port with `--port 0`, has somewhere to read the port it got.
  """

  use GenServer

  @type ref :: term()

  @doc "Open the listening socket. Options: `:ref`, `:port`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    ref = Keyword.fetch!(opts, :ref)
    GenServer.start_link(__MODULE__, opts, name: Jobq.Registry.via(ref, :socket))
  end

  @doc "The listening socket of the service `ref`."
  @spec socket(ref()) :: :gen_tcp.socket()
  def socket(ref), do: GenServer.call(Jobq.Registry.via(ref, :socket), :socket)

  @doc "The port the service `ref` listens on, which `--port 0` leaves to the kernel."
  @spec port(ref()) :: :inet.port_number()
  def port(ref), do: GenServer.call(Jobq.Registry.via(ref, :socket), :port)

  @impl GenServer
  def init(opts) do
    port = Keyword.fetch!(opts, :port)

    options = [
      :binary,
      active: false,
      reuseaddr: true,
      backlog: 1024,
      packet: :raw,
      nodelay: true
    ]

    case :gen_tcp.listen(port, options) do
      {:ok, socket} ->
        {:ok, bound} = :inet.port(socket)
        {:ok, %{socket: socket, port: bound}}

      {:error, reason} ->
        {:stop, {:bind, port, reason}}
    end
  end

  @impl GenServer
  def handle_call(:socket, _from, state), do: {:reply, state.socket, state}
  def handle_call(:port, _from, state), do: {:reply, state.port, state}
end
