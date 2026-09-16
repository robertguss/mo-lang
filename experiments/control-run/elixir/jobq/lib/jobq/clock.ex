defmodule Jobq.Clock do
  @moduledoc """
  The service's clock: milliseconds since the Unix epoch, and the ISO-8601 UTC
  rendering of that instant.

  A clock is a zero-arity function so a test can hand the queue a clock it
  moves by hand; `system/0` is the one `serve` uses.
  """

  @type t :: (-> integer())

  @doc "The system clock, in milliseconds since the Unix epoch."
  @spec system() :: t()
  def system, do: fn -> System.system_time(:millisecond) end

  @doc "Render a Unix millisecond instant as ISO-8601 UTC, e.g. `2026-09-15T23:59:00.123Z`."
  @spec iso8601(integer()) :: String.t()
  def iso8601(ms) when is_integer(ms) do
    ms |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()
  end
end
