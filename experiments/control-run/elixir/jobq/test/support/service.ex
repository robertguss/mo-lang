defmodule Jobq.Test.Service do
  @moduledoc """
  A service per test case: a temporary directory, a clock the test moves by
  hand unless it asks for the system's, and a free port.
  """

  alias Jobq.Server
  alias Jobq.Test.Clock

  @doc """
  Start a service for the calling test and return `%{ref: ref, dir: dir, port: port, clock: clock}`.

  Options are `Jobq.Server`'s, plus `:clock_at` for the starting instant of the
  test clock and `:system_clock?` to use the real one instead.
  """
  @spec start(keyword()) :: map()
  def start(opts \\ []) do
    ref = make_ref()
    dir = Keyword.get_lazy(opts, :dir, &tmp_dir/0)

    clock =
      Keyword.get_lazy(opts, :clock, fn ->
        Clock.new(Keyword.get(opts, :clock_at, 1_789_000_000_000))
      end)

    opts =
      opts
      |> Keyword.drop([:clock_at, :dir, :clock])
      |> Keyword.merge(ref: ref, dir: dir, port: Keyword.get(opts, :port, 0))
      |> Keyword.put(:clock, Clock.reader(clock))

    {:ok, pid} = Server.start_link(opts)
    ExUnit.Callbacks.on_exit(fn -> stop(pid) end)

    %{ref: ref, dir: dir, port: Server.port(ref), clock: clock, pid: pid}
  end

  @doc "Stop a service, waiting for it to be gone."
  @spec stop(pid()) :: :ok
  def stop(pid) do
    if Process.alive?(pid) do
      Supervisor.stop(pid)
    end
  catch
    :exit, _reason -> :ok
  end

  @doc "A fresh temporary directory, removed when the test ends."
  @spec tmp_dir() :: Path.t()
  def tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "jobq-test-#{System.unique_integer([:positive])}-#{:erlang.phash2(self())}"
      )

    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
