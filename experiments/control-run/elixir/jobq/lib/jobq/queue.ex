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

  A create may carry a `key`: the queue keeps a map from `{queue, key}` to the
  job that has it, rebuilt from the folder at every start, so a second create
  with the key answers the first job and makes nothing, until that job is
  deleted. The look has a third pass: a done or dead job left alone for
  `retain_ms` is moved to the archive (`Jobq.Archive.move/2`), leaves the
  board and its counts, and is still read by id and still holds its key.
  A prune (`Jobq.Prune.step/3`) removes the archived jobs older than an age,
  on request and, with a `retention_ms`, on a tick of its own, and frees
  their keys; it is one record, and a prune that removes nothing writes
  nothing.

  Nothing one request does to this process ends another: an operation runs
  inside a `try`, and whatever it raises, exits with, or throws is that
  request's `503` and no more. A store that could not write a batch tells the
  queue its new epoch; the queue answers by reloading its jobs from the log,
  which is the state the disk agrees with, so a request that was told `503`
  left the job it named exactly as it found it.
  """

  use GenServer

  require Logger

  alias Jobq.Board
  alias Jobq.Job
  alias Jobq.Rename
  alias Jobq.Store

  @type ref :: term()
  @type status :: 200 | 201 | 204 | 404 | 409
  @type reply :: {status(), Jobq.Json.value() | nil} | {:error, :store}
  @type operation ::
          {:create, String.t(), String.t(), pos_integer(), non_neg_integer(), non_neg_integer(),
           String.t() | nil}
          | {:get, String.t()}
          | {:list, String.t() | nil, Job.state() | nil, String.t() | nil}
          | {:delete, String.t()}
          | {:lease, String.t(), pos_integer(), String.t()}
          | {:ack, String.t(), String.t()}
          | {:fail, String.t(), String.t(), String.t() | nil}
          | {:retry, String.t()}
          | {:handoff, String.t(), String.t(), String.t()}
          | {:rename, String.t(), String.t()}
          | {:prune, pos_integer()}
          | :archive
          | :health
          | :queues

  @typep state :: %{
           ref: ref(),
           dir: Path.t(),
           clock: Jobq.Clock.t(),
           sweep_ms: pos_integer(),
           retain_ms: pos_integer(),
           retention_ms: non_neg_integer(),
           prune_every_ms: pos_integer(),
           started_at: integer(),
           counters: Board.counters(),
           jobs: %{pos_integer() => Job.t()},
           next: pos_integer(),
           queued: %{String.t() => :gb_sets.set(pos_integer())},
           leased: :gb_sets.set({integer(), pos_integer()}),
           scheduled: :gb_sets.set({integer(), pos_integer()}),
           finished: :gb_sets.set({integer(), pos_integer()}),
           archived: %{pos_integer() => Job.t()},
           keys: %{{String.t(), String.t()} => pos_integer()},
           counts: counts(),
           by_queue: %{String.t() => counts()},
           epoch: non_neg_integer()
         }

  @typep counts :: %{Job.state() => non_neg_integer()}

  # The spec's deadline for the queue: a request it has not answered in five
  # seconds is the service's failure, not the client's, and is a `503`.
  @call_timeout 5_000

  # Client

  @doc """
  Start the queue of the service `ref`. Options: `:ref`, `:dir`, `:clock`,
  `:sweep_ms`, `:retain_ms` (default a day), `:retention_ms` (default 0,
  never: the age the background prune removes), `:prune_every_ms` (default
  60,000), `:started_at`, and the service's `:counters`.

  The process takes its name only once it has read the log, so a request that
  arrives while the board is being rebuilt finds no queue and is answered
  `503` at once rather than held until the replay is over.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

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
  A `key` that already names a job of the queue answers `200` with that job,
  as it stands, and changes nothing.
  """
  @spec create(
          ref(),
          String.t(),
          String.t(),
          pos_integer(),
          non_neg_integer(),
          non_neg_integer(),
          String.t() | nil
        ) :: reply()
  def create(ref, queue, payload, max_tries, delay_ms \\ 0, backoff_ms \\ 0, key \\ nil),
    do: run(ref, {:create, queue, payload, max_tries, delay_ms, backoff_ms, key})

  @doc "Read a job. `GET /jobs/{id}`."
  @spec get(ref(), String.t()) :: reply()
  def get(ref, id), do: run(ref, {:get, id})

  @doc """
  List live jobs, at most 100, by id. `GET /jobs`. A `key` narrows the list to
  the live job of the queue that has it; an archived job is never listed.
  """
  @spec list(ref(), String.t() | nil, Job.state() | nil, String.t() | nil) :: reply()
  def list(ref, queue, state, key \\ nil), do: run(ref, {:list, queue, state, key})

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

  @doc """
  Hand a job the caller holds to the worker `to`, lease and tries as they are.
  `POST /jobs/{id}/handoff`.
  """
  @spec handoff(ref(), String.t(), String.t(), String.t()) :: reply()
  def handoff(ref, id, worker, to), do: run(ref, {:handoff, id, worker, to})

  @doc """
  Move every job of a queue, live or archived, to a queue that has none, in
  one record. `POST /queues/{name}/rename`.
  """
  @spec rename(ref(), String.t(), String.t()) :: reply()
  def rename(ref, from, to), do: run(ref, {:rename, from, to})

  @doc """
  Remove every archived job archived `older_than_ms` or more before now, in
  one record. `POST /archive/prune`.
  """
  @spec prune(ref(), pos_integer()) :: reply()
  def prune(ref, older_than_ms), do: run(ref, {:prune, older_than_ms})

  @doc "The archive's count, its oldest `archived_at`, and its bytes. `GET /archive`."
  @spec archive(ref()) :: reply()
  def archive(ref), do: run(ref, :archive)

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

    with {:ok, folder} <- Store.open(dir),
         {:ok, _owner} <- Registry.register(Jobq.Registry, {ref, :queue}, nil) do
      state =
        %{
          ref: ref,
          dir: dir,
          clock: clock,
          sweep_ms: sweep_ms,
          retain_ms: Keyword.get(opts, :retain_ms, 86_400_000),
          retention_ms: Keyword.get(opts, :retention_ms, 0),
          prune_every_ms: Keyword.get(opts, :prune_every_ms, 60_000),
          started_at: Keyword.get_lazy(opts, :started_at, clock),
          counters: Keyword.get_lazy(opts, :counters, &Board.counters/0),
          epoch: Store.epoch(ref)
        }
        |> load(folder)

      schedule_sweep(state)
      schedule_prune(state)
      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  # The board as the folder holds it, every index built again from nothing.
  defp load(state, %{jobs: jobs, next: next, archived: archived}) do
    state =
      Map.merge(state, %{
        jobs: %{},
        next: 1,
        queued: %{},
        leased: :gb_sets.new(),
        scheduled: :gb_sets.new(),
        finished: :gb_sets.new(),
        archived: %{},
        keys: %{},
        counts: zero(),
        by_queue: %{}
      })

    state = Enum.reduce(jobs, state, fn {_n, job}, state -> index_add(state, job) end)
    keys = Enum.reduce(archived, state.keys, fn {_n, job}, keys -> key_add(keys, job) end)
    %{state | jobs: jobs, next: next, archived: archived, keys: keys}
  end

  defp zero, do: %{queued: 0, scheduled: 0, leased: 0, done: 0, dead: 0}

  # A crash report carries the counts, not the jobs: a board is up to
  # millions of them, and their payloads are the clients'.
  @impl GenServer
  def format_status(status) do
    Map.update(status, :state, nil, fn
      %{jobs: jobs} = state ->
        %{state | jobs: {map_size(jobs), :jobs}, queued: :redacted, by_queue: :redacted}
        |> Map.merge(%{
          leased: :redacted,
          scheduled: :redacted,
          finished: :redacted,
          keys: :redacted,
          archived: {map_size(state.archived), :jobs}
        })

      other ->
        other
    end)
  end

  # The look is the board's and the operation is the request's: a look that
  # fails means a rule inside the service is broken, and the process ends so
  # the board is rebuilt from the log; an operation that fails is that
  # request's 503, and the state is left as the request found it.
  @impl GenServer
  def handle_call(operation, from, state) do
    {records, looked} = look(state)
    attempt(operation, records, from, looked, state)
  end

  defp attempt(operation, records, from, looked, state) do
    operate(operation, records, from, looked)
  rescue
    error ->
      Logger.error("jobq: #{inspect(operation)} failed: " <> Exception.message(error))
      {:reply, {:error, :store}, state}
  catch
    kind, reason ->
      Logger.error("jobq: #{inspect(operation)} failed: #{inspect(kind)} #{inspect(reason)}")
      {:reply, {:error, :store}, state}
  end

  defp operate(
         {:create, queue, _payload, _max_tries, _delay, _backoff, key},
         records,
         from,
         state
       )
       when is_map_key(state.keys, {queue, key}) do
    {:ok, job} = find_any(state, Map.fetch!(state.keys, {queue, key}))
    answer(state, records, from, {200, Job.render(job)})
  end

  defp operate(
         {:create, queue, payload, max_tries, delay_ms, backoff_ms, key},
         records,
         from,
         state
       ) do
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
        updated_at: now,
        key: key
      }
      |> delay(delay_ms, now)

    state = %{state | next: state.next + 1} |> put_job(job)
    answer(state, records ++ [{:put, job}], from, {201, Job.render(job)})
  end

  defp operate({:get, id}, records, from, state) do
    case find_any(state, id) do
      {:ok, job} -> answer(state, records, from, {200, Job.render(job)})
      :error -> answer(state, records, from, {404, error("no such job")})
    end
  end

  defp operate({:list, queue, job_state, key}, records, from, state) do
    jobs =
      state
      |> listed(queue, key)
      |> Enum.filter(fn job ->
        (is_nil(queue) or job.queue == queue) and (is_nil(job_state) or job.state == job_state)
      end)
      |> Enum.sort_by(& &1.n)
      |> Enum.take(100)
      |> Enum.map(&Job.render/1)

    answer(state, records, from, {200, {:obj, [{"jobs", jobs}]}})
  end

  defp operate({:delete, id}, records, from, state) do
    case find_any(state, id) do
      {:ok, %Job{state: :leased}} ->
        answer(state, records, from, {409, error("job is leased")})

      {:ok, %Job{archived_at: at} = job} when is_integer(at) ->
        state = %{
          state
          | archived: Map.delete(state.archived, job.n),
            keys: key_remove(state.keys, job)
        }

        answer(state, records ++ [{:unarchive, Job.id(job)}], from, {204, nil})

      {:ok, job} ->
        state = delete_job(state, job)
        answer(state, records ++ [{:delete, Job.id(job)}], from, {204, nil})

      :error ->
        answer(state, records, from, {404, error("no such job")})
    end
  end

  defp operate({:lease, queue, lease_ms, worker}, records, from, state) do
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

  defp operate({:ack, id, worker}, records, from, state) do
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

  defp operate({:fail, id, worker, reason}, records, from, state) do
    case held_by(state, id, worker) do
      {:ok, job} ->
        failed = %{after_try(job, state.clock.()) | reason: reason || job.reason}
        state = put_job(state, failed)
        answer(state, records ++ [{:put, failed}], from, {200, Job.render(failed)})

      {:error, status, message} ->
        answer(state, records, from, {status, error(message)})
    end
  end

  defp operate({:retry, id}, records, from, state) do
    case find_any(state, id) do
      {:ok, %Job{archived_at: at}} when is_integer(at) ->
        answer(state, records, from, {409, error("archived")})

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

  defp operate({:handoff, id, worker, to}, records, from, state) do
    with {:ok, job} <- find_any(state, id),
         {:ok, handed, changed?} <- Jobq.Handoff.step(job, worker, to, state.clock.()) do
      if changed? do
        state = put_job(state, handed)
        answer(state, records ++ [{:put, handed}], from, {200, Job.render(handed)})
      else
        answer(state, records, from, {200, Job.render(handed)})
      end
    else
      :error ->
        answer(state, records, from, {404, error("no such job")})

      :not_held ->
        answer(
          state,
          records,
          from,
          {409, error("caller does not hold a live lease on this job")}
        )
    end
  end

  # The jobs, the key map, and the two indexes that know a queue by name move
  # together; the deadline indexes and the counts do not know queues. `to`
  # has no job, so its rows are empty and taking `from`'s whole is the move.
  defp operate({:rename, name, to}, records, from, state) do
    case Rename.check([state.jobs, state.archived], name, to) do
      :ok ->
        {jobs, live} = Rename.jobs(state.jobs, name, to, state.next)
        {archived, gone} = Rename.jobs(state.archived, name, to, state.next)

        state = %{
          state
          | jobs: jobs,
            archived: archived,
            keys: Rename.keys(state.keys, name, to),
            queued: move_row(state.queued, name, to),
            by_queue: move_row(state.by_queue, name, to)
        }

        body = {:obj, [{"queue", to}, {"moved", live + gone}]}
        answer(state, records ++ [{:rename, name, to, state.next}], from, {200, body})

      :not_found ->
        answer(state, records, from, {404, error("no such queue")})

      :exists ->
        answer(state, records, from, {409, error("exists")})
    end
  end

  defp operate({:prune, older_than_ms}, records, from, state) do
    {state, pruned, cutoff} = prune_archive(state, older_than_ms)
    body = {:obj, [{"pruned", length(pruned)}, {"remaining", map_size(state.archived)}]}
    answer(state, records ++ prune_record(pruned, cutoff), from, {200, body})
  end

  defp operate(:archive, records, from, state) do
    oldest =
      case Enum.min_by(Map.values(state.archived), & &1.archived_at, fn -> nil end) do
        nil -> nil
        job -> Jobq.Clock.iso8601(job.archived_at)
      end

    bytes =
      case File.stat(Store.archive_path(state.dir)) do
        {:ok, stat} -> stat.size
        {:error, _reason} -> 0
      end

    body =
      {:obj,
       [{"archived", map_size(state.archived)}, {"oldest_archived_at", oldest}, {"bytes", bytes}]}

    answer(state, records, from, {200, body})
  end

  defp operate(:health, records, from, state) do
    body =
      {:obj,
       [
         {"queued", state.counts.queued},
         {"scheduled", state.counts.scheduled},
         {"leased", state.counts.leased},
         {"done", state.counts.done},
         {"dead", state.counts.dead},
         {"archived", map_size(state.archived)},
         {"uptime_ms", state.clock.() - state.started_at},
         {"restarts", Board.restarts(state.counters)}
       ]}

    answer(state, records, from, {200, body})
  end

  defp operate(:queues, records, from, state) do
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
    # Outside any `try`: a look that fails is the board's failure.
    {records, state} = look(state)
    if records != [], do: Store.commit(state.ref, records, nil, nil, state.epoch)
    schedule_sweep(state)
    {:noreply, state}
  end

  # The background prune: the look first, as every operation takes one, then
  # the prune, and only what changed is written.
  def handle_info(:prune, state) do
    {records, state} = look(state)
    {state, pruned, cutoff} = prune_archive(state, state.retention_ms)
    records = records ++ prune_record(pruned, cutoff)
    if records != [], do: Store.commit(state.ref, records, nil, nil, state.epoch)
    schedule_prune(state)
    {:noreply, state}
  end

  # A batch the store could not write. Everything this process had moved on
  # top of the log is dropped and the jobs are read back from it, so the state
  # the next request is answered off is the state on the disk; the commits
  # already on their way under the old epoch are refused by the store.
  def handle_info({:store_epoch, epoch}, state) do
    case Store.open(state.dir) do
      {:ok, folder} ->
        {:noreply, load(%{state | epoch: epoch}, folder)}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  defp move_row(rows, from, to) do
    case Map.pop(rows, from) do
      {nil, rows} -> rows
      {row, rows} -> Map.put(rows, to, row)
    end
  end

  defp schedule_sweep(state), do: Process.send_after(self(), :sweep, state.sweep_ms)

  defp schedule_prune(%{retention_ms: 0}), do: :ok

  defp schedule_prune(state) do
    _timer = Process.send_after(self(), :prune, state.prune_every_ms)
    :ok
  end

  # The prune's step over the archive and the key map, at the clock's reading.
  # The cutoff it used goes in the record, so the replay needs no clock.
  defp prune_archive(state, older_than_ms) do
    cutoff = Jobq.Prune.cutoff(state.clock.(), older_than_ms)
    {archived, keys, pruned} = Jobq.Prune.step(state.archived, state.keys, cutoff)
    {%{state | archived: archived, keys: keys}, pruned, cutoff}
  end

  defp prune_record([], _cutoff), do: []
  defp prune_record(pruned, cutoff), do: [{:prune, cutoff, length(pruned)}]

  # A look: every lease that has run out and every `run_at` that has passed by
  # the clock's reading, moved on. A lease that runs out on a job with a
  # backoff becomes scheduled at `now + backoff_ms`, which is after `now`, so
  # the two passes never chase each other.

  @spec look(state()) :: {[Store.record()], state()}
  defp look(state), do: look(state, state.clock.())

  defp look(state, now) do
    {state, records} = expire_leases(state, now, [])
    {state, records} = promote_scheduled(state, now, records)
    {state, records} = archive_finished(state, now, records)
    {Enum.reverse(records), state}
  end

  # A done or dead job whose `updated_at` is `retain_ms` or more before now
  # leaves the board for the archive; its key stays where it is.
  defp archive_finished(state, now, records) do
    case due(state.finished, now - state.retain_ms) do
      {:ok, n} ->
        job = Map.fetch!(state.jobs, n)
        {archived, [first, second]} = Jobq.Archive.move(job, now)
        state = drop_job(state, job)
        state = %{state | archived: Map.put(state.archived, n, archived)}
        archive_finished(state, now, [second, first | records])

      :none ->
        {state, records}
    end
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

  # A job on the board or in the archive, by its id or its counter.
  defp find_any(state, n) when is_integer(n) do
    case Map.fetch(state.jobs, n) do
      {:ok, job} -> {:ok, job}
      :error -> Map.fetch(state.archived, n)
    end
  end

  defp find_any(state, id) do
    case Job.parse_id(id) do
      {:ok, n} -> find_any(state, n)
      :error -> :error
    end
  end

  # The live jobs a listing looks at: all of them, or the one a key names.
  defp listed(state, _queue, nil), do: Map.values(state.jobs)

  defp listed(state, queue, key) do
    with {:ok, n} <- Map.fetch(state.keys, {queue, key}),
         {:ok, job} <- Map.fetch(state.jobs, n) do
      [job]
    else
      :error -> []
    end
  end

  defp held_by(state, id, worker) do
    case find_any(state, id) do
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

  # The state and its indexes: the queued jobs of a queue by id, the leased
  # jobs by the deadline their lease runs out at, the scheduled jobs by the
  # `run_at` they come due at, the done and dead jobs by the `updated_at` their
  # retention runs from, and the key map, which the archived jobs share.

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

  defp delete_job(state, job) do
    state = drop_job(state, job)
    %{state | keys: key_remove(state.keys, job)}
  end

  defp key_add(keys, %Job{key: nil}), do: keys
  defp key_add(keys, job), do: Map.put(keys, {job.queue, job.key}, job.n)

  defp key_remove(keys, %Job{key: nil}), do: keys
  defp key_remove(keys, job), do: Map.delete(keys, {job.queue, job.key})

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

      _finished ->
        %{state | finished: :gb_sets.delete_any({job.updated_at, job.n}, state.finished)}
    end
  end

  defp index_add(state, job) do
    state = state |> update_in([:counts, job.state], &(&1 + 1)) |> per_queue(job, 1)
    state = %{state | keys: key_add(state.keys, job)}

    case job.state do
      :queued ->
        set = Map.get(state.queued, job.queue, :gb_sets.new())
        %{state | queued: Map.put(state.queued, job.queue, :gb_sets.insert(job.n, set))}

      :leased ->
        %{state | leased: :gb_sets.insert({job.lease_until, job.n}, state.leased)}

      :scheduled ->
        %{state | scheduled: :gb_sets.insert({job.run_at, job.n}, state.scheduled)}

      _finished ->
        %{state | finished: :gb_sets.insert({job.updated_at, job.n}, state.finished)}
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
