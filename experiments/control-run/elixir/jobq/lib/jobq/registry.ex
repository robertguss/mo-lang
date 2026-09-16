defmodule Jobq.Registry do
  @moduledoc """
  Names for the processes of one service.

  A service is a tree with a `ref` of its own, so one node can run several of
  them: the tests run a service per test case, `jobq check` runs one beside the
  client that talks to it. Each process is registered under `{ref, role}`, and a
  restart puts the new process under the same name.
  """

  @doc "The registry's child specification, one per node."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts), do: Registry.child_spec(keys: :unique, name: __MODULE__)

  @doc "The `:via` name of `role` in the service `ref`."
  @spec via(term(), atom()) :: {:via, module(), {module(), {term(), atom()}}}
  def via(ref, role), do: {:via, Registry, {__MODULE__, {ref, role}}}

  @doc "The pid registered for `role` in the service `ref`, if there is one."
  @spec whereis(term(), atom()) :: pid() | nil
  def whereis(ref, role) do
    case Registry.lookup(__MODULE__, {ref, role}) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end
end
