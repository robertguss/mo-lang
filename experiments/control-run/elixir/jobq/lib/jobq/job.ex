defmodule Jobq.Job do
  @moduledoc """
  A job and the rules its fields must keep.

  A job's identity is a counter that never repeats in a service: `n` is the
  counter, `j_<n>` is what the API says. The struct carries everything a
  response and a store record need; `render/1` and `record/1` are the two
  shapes it is written in, both with their keys in a fixed order.
  """

  @enforce_keys [:n, :queue, :payload, :max_attempts, :state, :created_at, :updated_at]
  defstruct [
    :n,
    :queue,
    :payload,
    :max_attempts,
    :state,
    :created_at,
    :updated_at,
    :worker,
    :lease_until,
    :reason,
    attempts: 0
  ]

  @type state :: :queued | :leased | :done | :dead
  @type t :: %__MODULE__{
          n: pos_integer(),
          queue: String.t(),
          payload: String.t(),
          max_attempts: pos_integer(),
          attempts: non_neg_integer(),
          state: state(),
          created_at: integer(),
          updated_at: integer(),
          worker: String.t() | nil,
          lease_until: integer() | nil,
          reason: String.t() | nil
        }

  @queue_max 64
  @payload_max 61_440
  @reason_max 4_096
  @states %{"queued" => :queued, "leased" => :leased, "done" => :done, "dead" => :dead}

  @doc "The job's public id, `j_<counter>`."
  @spec id(t()) :: String.t()
  def id(%__MODULE__{n: n}), do: "j_" <> Integer.to_string(n)

  @doc "The counter inside a `j_<counter>` id, if the id has that shape."
  @spec parse_id(String.t()) :: {:ok, pos_integer()} | :error
  def parse_id("j_" <> digits) when byte_size(digits) > 0 and byte_size(digits) < 19 do
    case Integer.parse(digits) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end

  def parse_id(_), do: :error

  @doc "The state name the API and the store use."
  @spec state_name(state()) :: String.t()
  def state_name(state) when is_atom(state), do: Atom.to_string(state)

  @doc "A state name from the API or the store."
  @spec parse_state(term()) :: {:ok, state()} | :error
  def parse_state(name) when is_binary(name) do
    case Map.fetch(@states, name) do
      {:ok, state} -> {:ok, state}
      :error -> :error
    end
  end

  def parse_state(_), do: :error

  @doc """
  A queue name: 1 to 64 bytes of letters, digits, `-` and `_`.
  """
  @spec queue(term()) :: {:ok, String.t()} | {:error, String.t()}
  def queue(name) when is_binary(name) and byte_size(name) >= 1 and byte_size(name) <= @queue_max do
    if name =~ ~r/\A[A-Za-z0-9_-]+\z/,
      do: {:ok, name},
      else: {:error, "queue must be letters, digits, '-' or '_'"}
  end

  def queue(name) when is_binary(name),
    do: {:error, "queue must be 1 to #{@queue_max} bytes"}

  def queue(_), do: {:error, "queue must be a string"}

  @doc """
  A payload: 0 to 60 KiB of UTF-8 with no control characters but `\\n`.
  """
  @spec payload(term()) :: {:ok, String.t()} | {:error, String.t()}
  def payload(text) when is_binary(text) and byte_size(text) <= @payload_max do
    cond do
      not String.valid?(text) -> {:error, "payload must be UTF-8"}
      control_char?(text) -> {:error, "payload must have no control characters but '\\n'"}
      true -> {:ok, text}
    end
  end

  def payload(text) when is_binary(text), do: {:error, "payload must be at most 60 KiB"}
  def payload(_), do: {:error, "payload must be a string"}

  @doc "A fail reason: the payload's rule, at most 4 KiB."
  @spec reason(term()) :: {:ok, String.t()} | {:error, String.t()}
  def reason(text) when is_binary(text) and byte_size(text) <= @reason_max do
    cond do
      not String.valid?(text) -> {:error, "reason must be UTF-8"}
      control_char?(text) -> {:error, "reason must have no control characters but '\\n'"}
      true -> {:ok, text}
    end
  end

  def reason(text) when is_binary(text), do: {:error, "reason must be at most 4 KiB"}
  def reason(_), do: {:error, "reason must be a string"}

  @doc "`max_attempts`: an integer from 1 to 100."
  @spec max_attempts(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  def max_attempts(n) when is_integer(n) and n >= 1 and n <= 100, do: {:ok, n}
  def max_attempts(n) when is_integer(n), do: {:error, "max_attempts must be 1 to 100"}
  def max_attempts(_), do: {:error, "max_attempts must be an integer"}

  @doc "`lease_ms`: an integer from 100 to 3,600,000."
  @spec lease_ms(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  def lease_ms(n) when is_integer(n) and n >= 100 and n <= 3_600_000, do: {:ok, n}
  def lease_ms(n) when is_integer(n), do: {:error, "lease_ms must be 100 to 3600000"}
  def lease_ms(_), do: {:error, "lease_ms must be an integer"}

  defp control_char?(text) do
    text
    |> String.to_charlist()
    |> Enum.any?(fn c -> (c < 0x20 and c != ?\n) or c == 0x7F end)
  end

  @doc """
  The job as the API returns it: the common fields in a fixed order, then
  `worker` and `lease_until` while leased, then `reason` once it has one.
  """
  @spec render(t()) :: Jobq.Json.obj()
  def render(%__MODULE__{} = job) do
    base = [
      {"id", id(job)},
      {"queue", job.queue},
      {"state", state_name(job.state)},
      {"payload", job.payload},
      {"attempts", job.attempts},
      {"max_attempts", job.max_attempts},
      {"created_at", Jobq.Clock.iso8601(job.created_at)},
      {"updated_at", Jobq.Clock.iso8601(job.updated_at)}
    ]

    lease =
      if job.state == :leased,
        do: [{"worker", job.worker}, {"lease_until", Jobq.Clock.iso8601(job.lease_until)}],
        else: []

    reason = if job.reason, do: [{"reason", job.reason}], else: []

    {:obj, base ++ lease ++ reason}
  end

  @doc """
  The job as the store writes it: every field it needs to come back, with
  millisecond timestamps rather than their rendering.
  """
  @spec record(t()) :: Jobq.Json.obj()
  def record(%__MODULE__{} = job) do
    base = [
      {"id", id(job)},
      {"queue", job.queue},
      {"state", state_name(job.state)},
      {"payload", job.payload},
      {"attempts", job.attempts},
      {"max_attempts", job.max_attempts},
      {"created_at", job.created_at},
      {"updated_at", job.updated_at}
    ]

    lease =
      if job.state == :leased,
        do: [{"worker", job.worker}, {"lease_until", job.lease_until}],
        else: []

    reason = if job.reason, do: [{"reason", job.reason}], else: []

    {:obj, base ++ lease ++ reason}
  end

  @doc "A job back from a store record, or `:error` if the record is not one."
  @spec from_record(map()) :: {:ok, t()} | :error
  def from_record(%{} = map) do
    with {:ok, id} <- fetch(map, "id"),
         {:ok, n} <- parse_id(id),
         {:ok, queue} <- fetch(map, "queue"),
         {:ok, state_name} <- fetch(map, "state"),
         {:ok, state} <- parse_state(state_name),
         {:ok, payload} <- fetch(map, "payload"),
         {:ok, attempts} <- fetch(map, "attempts"),
         {:ok, max_attempts} <- fetch(map, "max_attempts"),
         {:ok, created_at} <- fetch(map, "created_at"),
         {:ok, updated_at} <- fetch(map, "updated_at"),
         true <- is_binary(queue) and is_binary(payload),
         true <- is_integer(attempts) and is_integer(max_attempts),
         true <- is_integer(created_at) and is_integer(updated_at) do
      {:ok,
       %__MODULE__{
         n: n,
         queue: queue,
         state: state,
         payload: payload,
         attempts: attempts,
         max_attempts: max_attempts,
         created_at: created_at,
         updated_at: updated_at,
         worker: optional(map, "worker"),
         lease_until: optional(map, "lease_until"),
         reason: optional(map, "reason")
       }}
    else
      _ -> :error
    end
  end

  def from_record(_), do: :error

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  defp optional(map, key), do: Map.get(map, key)
end
