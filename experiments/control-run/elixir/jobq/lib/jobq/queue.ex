defmodule Jobq.Queue do
  @moduledoc """
  The queue: every job of one service, and the only process that moves one.

  Because one process holds the whole state, a job's move from `queued` to
  `leased` is atomic against every other request without a lock, which is what
  keeps a job from being held by two workers. The process does not answer,
  though: it hands the records of the operation and the reply it owes to
  `Jobq.Store`, which answers once they are durable, and goes on to the next
  request while the disk catches up.

  A lease is a deadline, not a timer, and so is a scheduled job's `run_at`.
  Every operation takes a *look* first: leases that ran out by the clock's
  reading are moved on — back to `queued`, to `scheduled` when the job has a
  backoff, or to `dead` on its last try — and scheduled jobs whose `run_at` has
  passed are queued. Both moves are written before the operation's own reply.
  An idle service takes a look on a tick as well, so a lease that ran out or a
  delay that came due with nobody asking is still freed.

  Nothing one request does to this process ends another: an operation runs
  inside a `try`, and whatever it raises, exits with, or throws is that
  request's `503` and no more. A store that could not write a batch tells the
  queue its new epoch; the queue answers by reloading its jobs from the log,
  which is the state the disk agrees with, so a request that was told `503`
  left the job it named exactly as it found it.
  """

  use GenServer

  require Logger

  alias Jobq.Job
  alias Jobq.Store

  @type ref :: term()
  @type status :: 200 | 201 | 204 | 404 | 409
  @type reply :: {status(), Jobq.Json.value() | nil} | {:error, :store}
  @type operation ::
          {:create, String.t(), String.t(), pos_integer(), non_neg_integer(), non_neg_integer()}
          | {:get, String.t()}
          | {:list, String.t() | nil, Job.state() | nil}
          | {:delete, String.t()}
          | {:lease, String.t(), pos_integer(), String.t()}
          | {:ack, String.t(), String.t()}
          | {:fail, String.t(), String.t(), String.t() | nil}
          | {:retry, String.t()}
          | :health
          | :queues

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
           scheduled: :gb_sets.set({integer(), pos_integer()}),
           counts: counts(),
           by_queue: %{String.t() => counts()},
           epoch: non_neg_integer()
         }

  @typep counts :: %{Job.state() => non_neg_integer()}

  # The spec's deadline for the queue: a request it has not answered in five
  # seconds is the service's failure, not the client's, and is a `503`.
  @call_timeout 5_000

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

  @doc """
  Create a job. `POST /jobs`.

  `delay_ms` above 0 makes it scheduled until `created_at + delay_ms`;
  `backoff_ms` above 0 is how long it waits after a try that did not take.
  """
  @spec create(ref(), String.t(), String.t(), pos_integer(), non_neg_integer(), non_neg_integer()) ::
          reply()
  def create(ref, queue, payload, max_tries, delay_ms \\ 0, backoff_ms \\ 0),
    do: run(ref, {:create, queue, payload, max_tries, delay_ms, backoff_ms})

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

  @doc "Put a dead job back in its queue with its tries reset. `POST /jobs/{id}/retry`."
  @spec retry(ref(), String.t()) :: reply()
  def retry(ref, id), do: run(ref, {:retry, id})

  @doc "The counts and the uptime. `GET /health`."
  @spec health(ref()) :: reply()
  def health(ref), do: run(ref, :health)

  @doc "Every queue that has a job, with its counts per state. `GET /queues`."
  @spec queues(ref()) :: reply()
  def queues(ref), do: run(ref, :queues)

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
            scheduled: :gb_sets.new(),
            counts: zero(),
            by_queue: %{},
            epoch: Store.epoch(ref)
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

  defp zero, do: %{queued: 0, scheduled: 0, leased: 0, done: 0, dead: 0}

  @impl GenServer
  def handle_call(operation, from, state) do
    operate(operation, from, state)
  rescue
    error ->
      Logger.error("jobq: #{inspect(operation)} failed: " <> Exception.message(error))
      {:reply, {:error, :store}, state}
  catch
    kind, reason ->
      Logger.error("jobq: #{inspect(operation)} failed: #{inspect(kind)} #{inspect(reason)}")
      {:reply, {:error, :store}, state}
  end

  defp operate({:create, queue, payload, max_tries, delay_ms, backoff_ms}, from, state) do
    {records, state} = look(state)
    now = state.clock.()

    job =
      %Job{
        n: state.next,
        queue: queue,
        payload: payload,
        max_tries: max_tries,
        backoff_ms: backoff_ms,
        tries: 0,
        state: :queued,
        created_at: now,
        updated_at: now
      }
      |> delay(delay_ms, now)

    state = %{state | next: state.next + 1} |> put_job(job)
    answer(state, records ++ [{:put, job}], from, {201, Job.render(job)})
  end

  defp operate({:get, id}, from, state) do
    {records, state} = look(state)

    case find(state, id) do
      {:ok, job} -> answer(state, records, from, {200, Job.render(job)})
      :error -> answer(state, records, from, {404, error("no such job")})
    end
  end

  defp operate({:list, queue, job_state}, from, state) do
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

  defp operate({:delete, id}, from, state) do
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

  defp operate({:lease, queue, lease_ms, worker}, from, state) do
    {records, state} = look(state)

    case next_queued(state, queue) do
      {:ok, job} ->
        now = state.clock.()

        leased = %{
          job
          | state: :leased,
            tries: job.tries + 1,
            worker: worker,
            lease_until: now + lease_ms,
            run_at: nil,
            updated_at: now
        }

        state = put_job(state, leased)
        answer(state, records ++ [{:put, leased}], from, {200, Job.render(leased)})

      :error ->
        answer(state, records, from, {204, nil})
    end
  end

  defp operate({:ack, id, worker}, from, state) do
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

  defp operate({:fail, id, worker, reason}, from, state) do
    {records, state} = look(state)

    case held_by(state, id, worker) do
      {:ok, job} ->
        failed = %{after_try(job, state.clock.()) | reason: reason || job.reason}
        state = put_job(state, failed)
        answer(state, records ++ [{:put, failed}], from, {200, Job.render(failed)})

      {:error, status, message} ->
        answer(state, records, from, {status, error(message)})
    end
  end

  defp operate({:retry, id}, from, state) do
    {records, state} = look(state)

    case find(state, id) do
      {:ok, %Job{state: :dead} = job} ->
        now = state.clock.()

        queued = %{
          job
          | state: :queued,
            tries: 0,
            worker: nil,
            lease_until: nil,
            run_at: nil,
            reason: nil,
            updated_at: now
        }

        state = put_job(state, queued)
        answer(state, records ++ [{:put, queued}], from, {200, Job.render(queued)})

      {:ok, _job} ->
        answer(state, records, from, {409, error("job is not dead")})

      :error ->
        answer(state, records, from, {404, error("no such job")})
    end
  end

  defp operate(:health, from, state) do
    {records, state} = look(state)

    body =
      {:obj,
       [
         {"queued", state.counts.queued},
         {"scheduled", state.counts.scheduled},
         {"leased", state.counts.leased},
         {"done", state.counts.done},
         {"dead", state.counts.dead},
         {"uptime_ms", state.clock.() - state.started_at}
       ]}

    answer(state, records, from, {200, body})
  end

  defp operate(:queues, from, state) do
    {records, state} = look(state)

    queues =
      state.by_queue
      |> Enum.sort_by(fn {name, _counts} -> name end)
      |> Enum.map(fn {name, counts} ->
        {:obj,
         [
           {"name", name},
           {"queued", counts.queued},
           {"scheduled", counts.scheduled},
           {"leased", counts.leased},
           {"done", counts.done},
           {"dead", counts.dead}
         ]}
      end)

    answer(state, records, from, {200, {:obj, [{"queues", queues}]}})
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    {records, state} = look(state)
    if records != [], do: Store.commit(state.ref, records, nil, nil, state.epoch)
    schedule_sweep(state)
    {:noreply, state}
  end

  # A batch the store could not write. Everything this process had moved on
  # top of the log is dropped and the jobs are read back from it, so the state
  # the next request is answered off is the state on the disk; the commits
  # already on their way under the old epoch are refused by the store.
  def handle_info({:store_epoch, epoch}, state) do
    case Store.read(state.dir) do
      {:ok, {jobs, next}} ->
        state = %{
          state
          | jobs: %{},
            next: 1,
            queued: %{},
            leased: :gb_sets.new(),
            scheduled: :gb_sets.new(),
            counts: zero(),
            by_queue: %{},
            epoch: epoch
        }

        {:noreply, load(state, jobs, next)}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  defp schedule_sweep(state), do: Process.send_after(self(), :sweep, state.sweep_ms)

  # A look: every lease that has run out and every `run_at` that has passed by
  # the clock's reading, moved on. A lease that runs out on a job with a
  # backoff becomes scheduled at `now + backoff_ms`, which is after `now`, so
  # the two passes never chase each other.

  @spec look(state()) :: {[Store.record()], state()}
  defp look(state), do: look(state, state.clock.())

  defp look(state, now) do
    {state, records} = expire_leases(state, now, [])
    {state, records} = promote_scheduled(state, now, records)
    {Enum.reverse(records), state}
  end

  defp expire_leases(state, now, records) do
    case due(state.leased, now) do
      {:ok, n} ->
        job = Map.fetch!(state.jobs, n)
        moved = after_try(job, now)
        expire_leases(put_job(state, moved), now, [{:put, moved} | records])

      :none ->
        {state, records}
    end
  end

  defp promote_scheduled(state, now, records) do
    case due(state.scheduled, now) do
      {:ok, n} ->
        job = Map.fetch!(state.jobs, n)
        queued = %{job | state: :queued, run_at: nil, updated_at: now}
        promote_scheduled(put_job(state, queued), now, [{:put, queued} | records])

      :none ->
        {state, records}
    end
  end

  # The smallest deadline of a `{deadline, counter}` index, if it has passed.
  defp due(set, now) do
    if :gb_sets.is_empty(set) do
      :none
    else
      case :gb_sets.smallest(set) do
        {deadline, n} when deadline <= now -> {:ok, n}
        _later -> :none
      end
    end
  end

  # Where a job goes when a try did not take: a fail, or a lease that ran out.
  defp after_try(job, now) do
    cond do
      job.tries >= job.max_tries ->
        %{job | state: :dead, worker: nil, lease_until: nil, run_at: nil, updated_at: now}

      job.backoff_ms > 0 ->
        %{
          job
          | state: :scheduled,
            worker: nil,
            lease_until: nil,
            run_at: now + job.backoff_ms,
            updated_at: now
        }

      true ->
        %{job | state: :queued, worker: nil, lease_until: nil, run_at: nil, updated_at: now}
    end
  end

  defp delay(job, 0, _now), do: job
  defp delay(job, delay_ms, now), do: %{job | state: :scheduled, run_at: now + delay_ms}

  # Replies

  defp answer(state, [], _from, reply), do: {:reply, reply, state}

  defp answer(state, records, from, reply) do
    Store.commit(state.ref, records, from, reply, state.epoch)
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

  # The state and its three indexes: the queued jobs of a queue by id, the
  # leased jobs by the deadline their lease runs out at, and the scheduled jobs
  # by the `run_at` they come due at.

  defp put_job(state, job) do
    state =
      case Map.fetch(state.jobs, job.n) do
        {:ok, old} -> index_remove(state, old)
        :error -> state
      end

    state |> index_add(job) |> put_in([:jobs, job.n], job)
  end

  defp drop_job(state, job) do
    state = index_remove(state, job)
    %{state | jobs: Map.delete(state.jobs, job.n)}
  end

  defp index_remove(state, job) do
    state = state |> update_in([:counts, job.state], &(&1 - 1)) |> per_queue(job, -1)

    case job.state do
      :queued ->
        update_in(state, [:queued, job.queue], fn set ->
          :gb_sets.delete_any(job.n, set || :gb_sets.new())
        end)

      :leased ->
        %{state | leased: :gb_sets.delete_any({job.lease_until, job.n}, state.leased)}

      :scheduled ->
        %{state | scheduled: :gb_sets.delete_any({job.run_at, job.n}, state.scheduled)}

      _ ->
        state
    end
  end

  defp index_add(state, job) do
    state = state |> update_in([:counts, job.state], &(&1 + 1)) |> per_queue(job, 1)

    case job.state do
      :queued ->
        set = Map.get(state.queued, job.queue, :gb_sets.new())
        %{state | queued: Map.put(state.queued, job.queue, :gb_sets.insert(job.n, set))}

      :leased ->
        %{state | leased: :gb_sets.insert({job.lease_until, job.n}, state.leased)}

      :scheduled ->
        %{state | scheduled: :gb_sets.insert({job.run_at, job.n}, state.scheduled)}

      _ ->
        state
    end
  end

  # The counts `GET /queues` reads, one row per queue. A queue whose last job
  # is gone has no row, which is what makes it leave the list.
  defp per_queue(state, job, delta) do
    counts =
      state.by_queue
      |> Map.get(job.queue, zero())
      |> Map.update!(job.state, &(&1 + delta))

    by_queue =
      if Enum.all?(counts, fn {_state, count} -> count == 0 end),
        do: Map.delete(state.by_queue, job.queue),
        else: Map.put(state.by_queue, job.queue, counts)

    %{state | by_queue: by_queue}
  end
end
