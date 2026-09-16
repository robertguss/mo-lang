defmodule Jobq.Job do
  @moduledoc """
  A job and the rules its fields must keep.

  A job's identity is a counter that never repeats in a service: `n` is the
  counter, `j_<n>` is what the API says. The struct carries everything a
  response and a store record need; `render/1` and `record/1` are the two
  shapes it is written in, both with their keys in a fixed order.

  A job counts its leases in `tries` against `max_tries`, waits in `scheduled`
  until its `run_at` when it was created with a delay or put back with a
  backoff, and carries the `backoff_ms` it was created with for the rest of its
  life. `from_record/1` also reads the shape the version before this change
  wrote: `attempts` and `max_attempts` are `tries` and `max_tries`, and a
  record with no `backoff_ms` has none.

  `check_record/1` is the rule a record on the disk must meet before the
  service will serve the folder it is in: each field's own rule, and the state
  the record claims agreeing with the fields that state carries.
  """

  @enforce_keys [:n, :queue, :payload, :max_tries, :state, :created_at, :updated_at]
  defstruct [
    :n,
    :queue,
    :payload,
    :max_tries,
    :state,
    :created_at,
    :updated_at,
    :run_at,
    :worker,
    :lease_until,
    :reason,
    tries: 0,
    backoff_ms: 0
  ]

  @type state :: :queued | :scheduled | :leased | :done | :dead
  @type t :: %__MODULE__{
          n: pos_integer(),
          queue: String.t(),
          payload: String.t(),
          max_tries: pos_integer(),
          tries: non_neg_integer(),
          backoff_ms: non_neg_integer(),
          state: state(),
          created_at: integer(),
          updated_at: integer(),
          run_at: integer() | nil,
          worker: String.t() | nil,
          lease_until: integer() | nil,
          reason: String.t() | nil
        }

  @queue_max 64
  @payload_max 61_440
  @reason_max 4_096
  @states %{
    "queued" => :queued,
    "scheduled" => :scheduled,
    "leased" => :leased,
    "done" => :done,
    "dead" => :dead
  }

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

  @doc "The state names the API takes on a filter, in the order it names them."
  @spec state_names() :: [String.t()]
  def state_names, do: ~w(queued scheduled leased done dead)

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
  def queue(name)
      when is_binary(name) and byte_size(name) >= 1 and byte_size(name) <= @queue_max do
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

  @doc "`max_tries`: an integer from 1 to 100."
  @spec max_tries(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  def max_tries(n) when is_integer(n) and n >= 1 and n <= 100, do: {:ok, n}
  def max_tries(n) when is_integer(n), do: {:error, "max_tries must be 1 to 100"}
  def max_tries(_), do: {:error, "max_tries must be an integer"}

  @doc "`lease_ms`: an integer from 100 to 3,600,000."
  @spec lease_ms(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  def lease_ms(n) when is_integer(n) and n >= 100 and n <= 3_600_000, do: {:ok, n}
  def lease_ms(n) when is_integer(n), do: {:error, "lease_ms must be 100 to 3600000"}
  def lease_ms(_), do: {:error, "lease_ms must be an integer"}

  @doc "`delay_ms`: an integer from 0 to 86,400,000. It is not stored; `run_at` is."
  @spec delay_ms(term()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def delay_ms(n) when is_integer(n) and n >= 0 and n <= 86_400_000, do: {:ok, n}
  def delay_ms(n) when is_integer(n), do: {:error, "delay_ms must be 0 to 86400000"}
  def delay_ms(_), do: {:error, "delay_ms must be an integer"}

  @doc "`backoff_ms`: an integer from 0 to 3,600,000, fixed at creation."
  @spec backoff_ms(term()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def backoff_ms(n) when is_integer(n) and n >= 0 and n <= 3_600_000, do: {:ok, n}
  def backoff_ms(n) when is_integer(n), do: {:error, "backoff_ms must be 0 to 3600000"}
  def backoff_ms(_), do: {:error, "backoff_ms must be an integer"}

  defp control_char?(text) do
    text
    |> String.to_charlist()
    |> Enum.any?(fn c -> (c < 0x20 and c != ?\n) or c == 0x7F end)
  end

  @doc """
  The job as the API returns it: the common fields in a fixed order, then
  `run_at` while scheduled, then `worker` and `lease_until` while leased, then
  `reason` once it has one.
  """
  @spec render(t()) :: Jobq.Json.obj()
  def render(%__MODULE__{} = job) do
    base = [
      {"id", id(job)},
      {"queue", job.queue},
      {"state", state_name(job.state)},
      {"payload", job.payload},
      {"tries", job.tries},
      {"max_tries", job.max_tries},
      {"backoff_ms", job.backoff_ms},
      {"created_at", Jobq.Clock.iso8601(job.created_at)},
      {"updated_at", Jobq.Clock.iso8601(job.updated_at)}
    ]

    scheduled =
      if job.state == :scheduled, do: [{"run_at", Jobq.Clock.iso8601(job.run_at)}], else: []

    lease =
      if job.state == :leased,
        do: [{"worker", job.worker}, {"lease_until", Jobq.Clock.iso8601(job.lease_until)}],
        else: []

    reason = if job.reason, do: [{"reason", job.reason}], else: []

    {:obj, base ++ scheduled ++ lease ++ reason}
  end

  @doc """
  The job as the store writes it: every field it needs to come back, with
  millisecond timestamps rather than their rendering. Only the new names are
  ever written.
  """
  @spec record(t()) :: Jobq.Json.obj()
  def record(%__MODULE__{} = job) do
    base = [
      {"id", id(job)},
      {"queue", job.queue},
      {"state", state_name(job.state)},
      {"payload", job.payload},
      {"tries", job.tries},
      {"max_tries", job.max_tries},
      {"backoff_ms", job.backoff_ms},
      {"created_at", job.created_at},
      {"updated_at", job.updated_at}
    ]

    scheduled = if job.state == :scheduled, do: [{"run_at", job.run_at}], else: []

    lease =
      if job.state == :leased,
        do: [{"worker", job.worker}, {"lease_until", job.lease_until}],
        else: []

    reason = if job.reason, do: [{"reason", job.reason}], else: []

    {:obj, base ++ scheduled ++ lease ++ reason}
  end

  @doc """
  A job back from a store record, or `:error` if the record is not one.

  A record the version before this change wrote is read too: `attempts` is
  `tries`, `max_attempts` is `max_tries`, and a record with no `backoff_ms` has
  a backoff of 0. A record that says it is scheduled needs its `run_at`.
  """
  @spec from_record(map()) :: {:ok, t()} | :error
  def from_record(%{} = map) do
    with {:ok, id} <- fetch(map, "id"),
         {:ok, n} <- parse_id(id),
         {:ok, queue} <- fetch(map, "queue"),
         {:ok, state_name} <- fetch(map, "state"),
         {:ok, state} <- parse_state(state_name),
         {:ok, payload} <- fetch(map, "payload"),
         {:ok, tries} <- fetch_either(map, "tries", "attempts"),
         {:ok, max_tries} <- fetch_either(map, "max_tries", "max_attempts"),
         {:ok, backoff_ms} <- fetch_or(map, "backoff_ms", 0),
         {:ok, created_at} <- fetch(map, "created_at"),
         {:ok, updated_at} <- fetch(map, "updated_at"),
         {:ok, run_at} <- fetch_run_at(map, state),
         true <- is_binary(queue) and is_binary(payload),
         true <- is_integer(tries) and is_integer(max_tries) and is_integer(backoff_ms),
         true <- is_integer(created_at) and is_integer(updated_at) do
      {:ok,
       %__MODULE__{
         n: n,
         queue: queue,
         state: state,
         payload: payload,
         tries: tries,
         max_tries: max_tries,
         backoff_ms: backoff_ms,
         created_at: created_at,
         updated_at: updated_at,
         run_at: run_at,
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

  # The new name, or the name the previous version wrote.
  defp fetch_either(map, key, old_key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> fetch(map, old_key)
    end
  end

  defp fetch_or(map, key, default), do: {:ok, Map.get(map, key, default)}

  # A scheduled job is its `run_at`; any other state has none, whatever the
  # record carries.
  defp fetch_run_at(map, :scheduled) do
    case Map.fetch(map, "run_at") do
      {:ok, run_at} when is_integer(run_at) -> {:ok, run_at}
      _other -> :error
    end
  end

  defp fetch_run_at(_map, _state), do: {:ok, nil}

  defp optional(map, key), do: Map.get(map, key)

  @doc """
  The rule a store record breaks, or `:ok` when it is well-formed.

  One function over the raw record, the whole rule in one place: the key names
  the job's id, every field keeps its own rule under the current name or the
  one the version before change 1 wrote, and the state says which of `run_at`,
  `worker` and `lease_until` the record must carry and which it must not.

      queued     tries < max_tries; no run_at, worker, lease_until
      scheduled  tries < max_tries; run_at present; no worker, lease_until
      leased     1 <= tries <= max_tries; worker and lease_until; no run_at
      done       1 <= tries <= max_tries; no run_at, worker, lease_until
      dead       1 <= tries <= max_tries; no run_at, worker, lease_until

  A `reason` belongs to no state in particular: a job carries the one it was
  last failed with until a retry drops it.
  """
  @spec check_record(term()) :: :ok | {:error, String.t()}
  def check_record(%{} = map) do
    with :ok <- check_key(map),
         {:ok, state} <- check_state(map),
         :ok <- check_required(map, "queue", &queue/1),
         :ok <- check_required(map, "payload", &payload/1),
         :ok <- check_either(map, "max_tries", "max_attempts", &max_tries/1),
         :ok <- check_tries(map),
         :ok <- check_present(map, "backoff_ms", &backoff_ms/1),
         :ok <- check_required(map, "created_at", &instant(&1, "created_at")),
         :ok <- check_required(map, "updated_at", &instant(&1, "updated_at")),
         :ok <- check_present(map, "reason", &reason/1) do
      check_shape(map, state)
    end
  end

  def check_record(_other), do: {:error, "a record must be a JSON object"}

  @doc """
  The key a record is filed under: its `id`, or `?` when it does not have one
  a message can name.
  """
  @spec record_key(term()) :: String.t()
  def record_key(%{"id" => id}) when is_binary(id) and byte_size(id) <= 64, do: id
  def record_key(_other), do: "?"

  defp check_key(map) do
    with {:ok, id} when is_binary(id) <- fetch(map, "id"),
         {:ok, _n} <- parse_id(id) do
      :ok
    else
      _ -> {:error, "the key must name the job's id, 'j_' and a counter"}
    end
  end

  defp check_state(map) do
    case fetch(map, "state") do
      {:ok, name} ->
        case parse_state(name) do
          {:ok, state} -> {:ok, state}
          :error -> {:error, "state must be queued, scheduled, leased, done or dead"}
        end

      :error ->
        {:error, "'state' is required"}
    end
  end

  defp check_required(map, key, rule) do
    case Map.fetch(map, key) do
      {:ok, value} -> checked(rule.(value))
      :error -> {:error, "'#{key}' is required"}
    end
  end

  defp check_either(map, key, old_key, rule) do
    case fetch_either(map, key, old_key) do
      {:ok, value} -> checked(rule.(value))
      :error -> {:error, "'#{key}' is required"}
    end
  end

  # A field a record may leave out: the old shape has no `backoff_ms`, and a
  # job that was never failed has no `reason`.
  defp check_present(map, key, rule) do
    case Map.fetch(map, key) do
      {:ok, nil} -> :ok
      {:ok, value} -> checked(rule.(value))
      :error -> :ok
    end
  end

  defp checked({:ok, _value}), do: :ok
  defp checked({:error, message}), do: {:error, message}

  defp check_tries(map) do
    case fetch_either(map, "tries", "attempts") do
      {:ok, tries} when is_integer(tries) and tries >= 0 -> :ok
      {:ok, tries} when is_integer(tries) -> {:error, "tries must be 0 or more"}
      {:ok, _other} -> {:error, "tries must be an integer"}
      :error -> {:error, "'tries' is required"}
    end
  end

  defp instant(value, _name) when is_integer(value), do: {:ok, value}
  defp instant(_value, name), do: {:error, "#{name} must be an instant in milliseconds"}

  defp check_shape(map, state) do
    with :ok <- check_count(map, state) do
      case state do
        :queued -> without(map, ["run_at", "worker", "lease_until"], "queued")
        :scheduled -> with_run_at(map)
        :leased -> with_lease(map)
        :done -> without(map, ["run_at", "worker", "lease_until"], "done")
        :dead -> without(map, ["run_at", "worker", "lease_until"], "dead")
      end
    end
  end

  # A job that has not been leased yet has a try left; a job that has been
  # leased has used at least one and never more than its max.
  defp check_count(map, state) do
    tries = count(map, "tries", "attempts")
    max = count(map, "max_tries", "max_attempts")

    cond do
      state in [:queued, :scheduled] and tries >= max ->
        {:error, "a #{state_name(state)} job has tried fewer times than its max_tries"}

      state in [:leased, :done, :dead] and (tries < 1 or tries > max) ->
        {:error, "a #{state_name(state)} job has tried at least once and at most its max_tries"}

      true ->
        :ok
    end
  end

  defp count(map, key, old_key) do
    case fetch_either(map, key, old_key) do
      {:ok, value} when is_integer(value) -> value
      _other -> 0
    end
  end

  defp with_run_at(map) do
    case present(map, "run_at") do
      {:ok, run_at} when is_integer(run_at) ->
        without(map, ["worker", "lease_until"], "scheduled")

      {:ok, _other} ->
        {:error, "a scheduled job's run_at is an instant in milliseconds"}

      :error ->
        {:error, "a scheduled job has a run_at"}
    end
  end

  defp with_lease(map) do
    with {:ok, worker} when is_binary(worker) <- present(map, "worker"),
         {:ok, until} when is_integer(until) <- present(map, "lease_until") do
      without(map, ["run_at"], "leased")
    else
      _ -> {:error, "a leased job has a worker and a lease_until"}
    end
  end

  defp present(map, key) do
    case Map.fetch(map, key) do
      {:ok, nil} -> :error
      other -> other
    end
  end

  defp without(map, keys, state) do
    case Enum.find(keys, fn key -> match?({:ok, _value}, present(map, key)) end) do
      nil -> :ok
      key -> {:error, "a #{state} job has no #{key}"}
    end
  end
end
