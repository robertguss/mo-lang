defmodule Jobq.Application do
  @moduledoc """
  The node's application: the process registry every service registers in.

  No service starts here. `jobq serve` and `jobq check` start a `Jobq.Server`
  with the directory and the port they were given, and a test starts one per
  case.
  """

  use Application

  @impl Application
  def start(_type, _args) do
    Supervisor.start_link([Jobq.Registry], strategy: :one_for_one, name: Jobq.Node)
  end
end
