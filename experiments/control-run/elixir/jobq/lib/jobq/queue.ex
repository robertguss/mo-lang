defmodule Jobq.Queue do
  @moduledoc """
  The queue: every job of one service, and the only process that moves one.

  Because one process holds the whole state, a job's move from `queued` to
  `leased` is atomic against every other request without a lock, which is what
  keeps a job from being held by two workers. The process does not answer,
  though: it hands the records of the operation and the reply it owes to
  `Jobq.Store`, which answers once they are durable, and goes on to the next
  request while the disk catches up.

  A lease is a deadline, not a timer. Every operation takes a *look* first:
  leases that ran out by the clock's reading are moved back to `queued`, or to
  `dead` on their last attempt, and those moves are written before the
  operation's own reply. An idle service takes a look on a tick as well, so a
  lease that ran out with nobody asking is still freed.
  """

  use GenServer

  alias Jobq.Job
  alias Jobq.Store

  @type ref :: term()
  @type status :: 200 | 201 | 204 | 404 | 409
  @type reply :: {status(), Jobq.Json.value() | nil} | {:error, :store}
  @type operation ::
          {:create, String.t(), String.t(), pos_integer()}
          | {:get, String.t()}
          | {:list, String.t() | nil, Job.state() | nil}
          | {:delete, String.t()}
          | {:lease, String.t(), pos_integer(), String.t()}
          | {:ack, String.t(), String.t()}
          | {:fail, String.t(), String.t(), String.t() | nil}
          | :health

  @typep state :: %{
           ref: ref(),
           dir: Path.t(),
           clock: Jobq.Clock.t(),
           sweep_ms: pos_integer(),
           started_at: integer(),
           jobs: %{pos_integer() => Job.t()},
           next: pos_integer(),
           queued: %{String.t() => :gb_sets.set(pos_integer())},
           leased: :gb_sets.set({integer(), pos_integer()}),
           counts: %{Job.state() => non_neg_integer()}
         }

  @call_timeout 15_000

  # Client

  @doc "Start the queue of the service `ref`. Options: `:ref`, `:dir`, `:clock`, `:sweep_ms`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    ref = Keyword.fetch!(opts, :ref)
    GenServer.start_link(__MODULE__, opts, name: Jobq.Registry.via(ref, :queue))
  end

  @doc """
  Run one operation and wait for its reply, which for anything that writes
  comes back once the write is durable. A queue that is down or too slow is
  `{:error, :store}`, which the router answers with `503`.
  """
  @spec run(ref(), operation()) :: reply()
  def run(ref, operation) do
    GenServer.call(Jobq.Registry.via(ref, :queue), operation, @call_timeout)
  catch
    :exit, _reason -> {:error, :store}
  end

  @doc "Create a job. `POST /jobs`."
  @spec create(ref(), String.t(), String.t(), pos_integer()) :: reply()
  def create(ref, queue, payload, max_attempts),
    do: run(ref, {:create, queue, payload, max_attempts})

  @doc "Read a job. `GET /jobs/{id}`."
  @spec get(ref(), String.t()) :: reply()
  def get(ref, id), do: run(ref, {:get, id})

  @doc "List jobs, at most 100, by id. `GET /jobs`."
  @spec list(ref(), String.t() | nil, Job.state() | nil) :: reply()
  def list(ref, queue, state), do: run(ref, {:list, queue, state})

  @doc "Delete a job that is not leased. `DELETE /jobs/{id}`."
  @spec delete(ref(), String.t()) :: reply()
  def delete(ref, id), do: run(ref, {:delete, id})

  @doc "Lease the oldest queued job of a queue. `POST /queues/{queue}/lease`."
  @spec lease(ref(), String.t(), pos_integer(), String.t()) :: reply()
  def lease(ref, queue, lease_ms, worker), do: run(ref, {:lease, queue, lease_ms, worker})

  @doc "Ack a job the caller holds. `POST /jobs/{id}/ack`."
  @spec ack(ref(), String.t(), String.t()) :: reply()
  def ack(ref, id, worker), do: run(ref, {:ack, id, worker})

  @doc "Fail a job the caller holds. `POST /jobs/{id}/fail`."
  @spec fail(ref(), String.t(), String.t(), String.t() | nil) :: reply()
  def fail(ref, id, worker, reason), do: run(ref, {:fail, id, worker, reason})

  @doc "The counts and the uptime. `GET /health`."
  @spec health(ref()) :: reply()
  def health(ref), do: run(ref, :health)

  # Server

  @impl GenServer
  def init(opts) do
    ref = Keyword.fetch!(opts, :ref)
    dir = Keyword.fetch!(opts, :dir)
    clock = Keyword.get(opts, :clock, Jobq.Clock.system())
    sweep_ms = Keyword.get(opts, :sweep_ms, 100)

    case Store.read(dir) do
      {:ok, {jobs, next}} ->
        state =
          %{
            ref: ref,
            dir: dir,
            clock: clock,
            sweep_ms: sweep_ms,
            started_at: clock.(),
            jobs: %{},
            next: 1,
            queued: %{},
            leased: :gb_sets.new(),
            counts: %{queued: 0, leased: 0, done: 0, dead: 0}
          }
          |> load(jobs, next)

        schedule_sweep(state)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp load(state, jobs, next) do
    state = Enum.reduce(jobs, state, fn {_n, job}, state -> index_add(state, job) end)
    %{state | jobs: jobs, next: next}
  end

  @impl GenServer
  def handle_call({:create, queue, payload, max_attempts}, from, state) do
    {records, state} = look(state)
    now = state.clock.()

    job = %Job{
      n: state.next,
      queue: queue,
      payload: payload,
      max_attempts: max_attempts,
      attempts: 0,
      state: :queued,
      created_at: now,
      updated_at: now
    }

    state = %{state | next: state.next + 1} |> put_job(job)
    answer(state, records ++ [{:put, job}], from, {201, Job.render(job)})
  end

  def handle_call({:get, id}, from, state) do
    {records, state} = look(state)

    case find(state, id) do
      {:ok, job} -> answer(state, records, from, {200, Job.render(job)})
      :error -> answer(state, records, from, {404, error("no such job")})
    end
  end

  def handle_call({:list, queue, job_state}, from, state) do
    {records, state} = look(state)

    jobs =
      state.jobs
      |> Map.values()
      |> Enum.filter(fn job ->
        (is_nil(queue) or job.queue == queue) and (is_nil(job_state) or job.state == job_state)
      end)
      |> Enum.sort_by(& &1.n)
      |> Enum.take(100)
      |> Enum.map(&Job.render/1)

    answer(state, records, from, {200, {:obj, [{"jobs", jobs}]}})
  end

  def handle_call({:delete, id}, from, state) do
    {records, state} = look(state)

    case find(state, id) do
      {:ok, %Job{state: :leased}} ->
        answer(state, records, from, {409, error("job is leased")})

      {:ok, job} ->
        state = drop_job(state, job)
        answer(state, records ++ [{:delete, Job.id(job)}], from, {204, nil})

      :error ->
        answer(state, records, from, {404, error("no such job")})
    end
  end

  def handle_call({:lease, queue, lease_ms, worker}, from, state) do
    {records, state} = look(state)

    case next_queued(state, queue) do
      {:ok, job} ->
        now = state.clock.()

        leased = %{
          job
          | state: :leased,
            attempts: job.attempts + 1,
            worker: worker,
            lease_until: now + lease_ms,
            updated_at: now
        }

        state = put_job(state, leased)
        answer(state, records ++ [{:put, leased}], from, {200, Job.render(leased)})

      :error ->
        answer(state, records, from, {204, nil})
    end
  end

  def handle_call({:ack, id, worker}, from, state) do
    {records, state} = look(state)

    case held_by(state, id, worker) do
      {:ok, job} ->
        now = state.clock.()
        done = %{job | state: :done, worker: nil, lease_until: nil, updated_at: now}
        state = put_job(state, done)
        answer(state, records ++ [{:put, done}], from, {200, Job.render(done)})

      {:error, status, message} ->
        answer(state, records, from, {status, error(message)})
    end
  end

  def handle_call({:fail, id, worker, reason}, from, state) do
    {records, state} = look(state)

    case held_by(state, id, worker) do
      {:ok, job} ->
        failed = %{give_up_or_requeue(job, state.clock.()) | reason: reason || job.reason}
        state = put_job(state, failed)
        answer(state, records ++ [{:put, failed}], from, {200, Job.render(failed)})

      {:error, status, message} ->
        answer(state, records, from, {status, error(message)})
    end
  end

  def handle_call(:health, from, state) do
    {records, state} = look(state)

    body =
      {:obj,
       [
         {"queued", state.counts.queued},
         {"leased", state.counts.leased},
         {"done", state.counts.done},
         {"dead", state.counts.dead},
         {"uptime_ms", state.clock.() - state.started_at}
       ]}

    answer(state, records, from, {200, body})
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    {records, state} = look(state)
    if records != [], do: Store.commit(state.ref, records, nil, nil)
    schedule_sweep(state)
    {:noreply, state}
  end

  defp schedule_sweep(state), do: Process.send_after(self(), :sweep, state.sweep_ms)

  # A look: every lease that has run out by the clock's reading, moved back.

  @spec look(state()) :: {[Store.record()], state()}
  defp look(state), do: look(state, state.clock.(), [])

  defp look(state, now, records) do
    case :gb_sets.is_empty(state.leased) do
      true ->
        {Enum.reverse(records), state}

      false ->
        {{lease_until, n}, rest} = :gb_sets.take_smallest(state.leased)

        if lease_until <= now do
          job = Map.fetch!(state.jobs, n)
          moved = give_up_or_requeue(job, now)
          state = %{state | leased: rest} |> put_job(moved, skip_index_remove: true)
          look(state, now, [{:put, moved} | records])
        else
          {Enum.reverse(records), state}
        end
    end
  end

  defp give_up_or_requeue(job, now) do
    state = if job.attempts >= job.max_attempts, do: :dead, else: :queued
    %{job | state: state, worker: nil, lease_until: nil, updated_at: now}
  end

  # Replies

  defp answer(state, [], _from, reply), do: {:reply, reply, state}

  defp answer(state, records, from, reply) do
    Store.commit(state.ref, records, from, reply)
    {:noreply, state}
  end

  defp error(message), do: {:obj, [{"error", message}]}

  # Lookups

  defp find(state, id) do
    with {:ok, n} <- Job.parse_id(id), {:ok, job} <- Map.fetch(state.jobs, n) do
      {:ok, job}
    else
      _ -> :error
    end
  end

  defp held_by(state, id, worker) do
    case find(state, id) do
      {:ok, %Job{state: :leased, worker: ^worker} = job} -> {:ok, job}
      {:ok, _job} -> {:error, 409, "caller does not hold a live lease on this job"}
      :error -> {:error, 404, "no such job"}
    end
  end

  defp next_queued(state, queue) do
    with {:ok, set} <- Map.fetch(state.queued, queue),
         false <- :gb_sets.is_empty(set) do
      {:ok, Map.fetch!(state.jobs, :gb_sets.smallest(set))}
    else
      _ -> :error
    end
  end

  # The state and its two indexes: the queued jobs of a queue by id, and the
  # leased jobs by the deadline their lease runs out at.

  defp put_job(state, job, opts \\ []) do
    state =
      case Map.fetch(state.jobs, job.n) do
        {:ok, old} -> index_remove(state, old, Keyword.get(opts, :skip_index_remove, false))
        :error -> state
      end

    state |> index_add(job) |> put_in([:jobs, job.n], job)
  end

  defp drop_job(state, job) do
    state = index_remove(state, job, false)
    %{state | jobs: Map.delete(state.jobs, job.n)}
  end

  defp index_remove(state, job, skip_set) do
    state = update_in(state, [:counts, job.state], &(&1 - 1))

    case job.state do
      :queued ->
        update_in(state, [:queued, job.queue], fn set ->
          :gb_sets.delete_any(job.n, set || :gb_sets.new())
        end)

      :leased when not skip_set ->
        %{state | leased: :gb_sets.delete_any({job.lease_until, job.n}, state.leased)}

      _ ->
        state
    end
  end

  defp index_add(state, job) do
    state = update_in(state, [:counts, job.state], &(&1 + 1))

    case job.state do
      :queued ->
        set = Map.get(state.queued, job.queue, :gb_sets.new())
        %{state | queued: Map.put(state.queued, job.queue, :gb_sets.insert(job.n, set))}

      :leased ->
        %{state | leased: :gb_sets.insert({job.lease_until, job.n}, state.leased)}

      _ ->
        state
    end
  end
end
