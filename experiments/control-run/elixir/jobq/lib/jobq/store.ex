defmodule Jobq.Store do
  @moduledoc """
  The store: an append-only log of job records, one JSON object per line.

  The process owns the log. A caller hands it the records of one operation
  together with the reply that operation owes its client; the process writes
  them, `fsync`s, and only then sends the reply. Records that arrive while a
  write is in flight are written and synced together, so a busy service pays
  one `fsync` for many jobs and no reply is ever sent before its own record is
  on the disk.

  A batch is written through a file the process opens for it and closes again.
  That is what makes a folder that has been made unwritable visible to the
  very next write rather than to the next restart, and what lets writes resume
  on their own once it can be written again: the cost is one `open` and one
  `close` beside an `fsync` that dominates them both.

  A write or a sync that fails is not papered over and does not take the
  service down either: the waiters of that batch are told the store is down
  (the router turns that into a `503`), the batch is dropped, and the store
  moves to a new *epoch*. The queue is told the new epoch and answers it by
  reloading its jobs from the log, which is the state the disk agrees with; a
  commit that was already on its way under the old epoch is refused rather
  than written, so nothing a `503` was sent for can land on the disk later.

  The log's framing is one line per record, `\\n` terminated, under the job's
  id; the last line of a log may be torn by a crash and is dropped on replay, a
  complete line that is not a JSON object is a corrupt log, and an object that
  is not a well-formed record refuses the folder by `Jobq.Job.check_record/1`.

  A log the version before change 1 wrote opens with no tool: `Jobq.Job` reads
  the old field names off a record and the store writes only the new ones, so
  a `compact/1` of such a folder leaves no old name behind.
  """

  use GenServer

  require Logger

  alias Jobq.Job
  alias Jobq.Json

  @log_name "jobq.log"
  @max_batch 512

  @type ref :: term()
  @type record :: {:put, Job.t()} | {:delete, String.t()}
  @type log :: {%{pos_integer() => Job.t()}, pos_integer()}

  @typep state :: %{
           path: String.t(),
           buffer: iodata(),
           waiters: [{GenServer.from(), term()}],
           batch: non_neg_integer(),
           epoch: non_neg_integer(),
           ref: ref(),
           fault: (non_neg_integer() -> boolean())
         }

  # Client

  @doc "Start the writer for `dir`. Options: `:ref`, `:dir`, and a test `:fault`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    ref = Keyword.fetch!(opts, :ref)
    GenServer.start_link(__MODULE__, opts, name: Jobq.Registry.via(ref, :store))
  end

  @doc """
  Write the records of one operation and, once they are durable, send `reply`
  to `from`. `from` may be `nil` for a write no client is waiting on.

  `epoch` is the caller's reading of the store's epoch; a commit from an epoch
  the store has left is refused with `{:error, :store}` and written nowhere.
  """
  @spec commit(ref(), [record()], GenServer.from() | nil, term(), non_neg_integer()) :: :ok
  def commit(ref, records, from, reply, epoch) do
    GenServer.cast(Jobq.Registry.via(ref, :store), {:commit, records, from, reply, epoch})
  end

  @doc "The store's epoch, which the queue tags its commits with."
  @spec epoch(ref()) :: non_neg_integer()
  def epoch(ref), do: GenServer.call(Jobq.Registry.via(ref, :store), :epoch, 30_000)

  @doc "Wait until everything written so far is durable."
  @spec sync(ref()) :: :ok | {:error, term()}
  def sync(ref), do: GenServer.call(Jobq.Registry.via(ref, :store), :sync, 30_000)

  @doc "The log's path inside `dir`."
  @spec log_path(Path.t()) :: Path.t()
  def log_path(dir), do: Path.join(dir, @log_name)

  # Reading and compacting, without a process

  @doc """
  Replay `dir`'s log into the live jobs, oldest record last write wins.

  Returns the jobs by id counter and the counter the next id is taken from. A
  torn final line is dropped; a complete line that is not a JSON object is
  `{:error, {:corrupt, line_number}}`, and one that is an object but not a
  well-formed record is `{:error, {:record, key, rule}}`.
  """
  @spec read(Path.t()) ::
          {:ok, log()} | {:error, {:corrupt, pos_integer()} | {:record, String.t(), String.t()}}
  def read(dir) do
    path = log_path(dir)

    case File.read(path) do
      {:ok, bytes} -> replay(bytes)
      {:error, :enoent} -> {:ok, {%{}, 1}}
      {:error, reason} -> {:error, {:open, path, reason}}
    end
  end

  @doc """
  Rewrite `dir`'s log to one line per live job, by id, through a temporary file
  and a rename. A folder that does not open is not rewritten, so a compaction
  writes well-formed records only.
  """
  @spec compact(Path.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def compact(dir) do
    with {:ok, {jobs, next}} <- read(dir) do
      path = log_path(dir)
      tmp = path <> ".compact"
      highest = jobs |> Map.keys() |> Enum.max(fn -> 0 end)

      marker =
        if next > highest + 1,
          do: [[Json.encode({:obj, [{"next", next}]}), ?\n]],
          else: []

      lines =
        marker ++
          (jobs
           |> Enum.sort_by(fn {n, _job} -> n end)
           |> Enum.map(fn {_n, job} -> [Json.encode(Job.record(job)), ?\n] end))

      with {:ok, fd} <- :file.open(tmp, [:write, :raw, :binary]),
           :ok <- write_and_close(fd, lines),
           :ok <- :file.rename(tmp, path),
           :ok <- sync_dir(dir) do
        {:ok, map_size(jobs)}
      else
        {:error, reason} ->
          _ = File.rm(tmp)
          {:error, {:compact, reason}}
      end
    end
  end

  defp write_and_close(fd, lines) do
    with :ok <- :file.write(fd, lines),
         :ok <- :file.sync(fd) do
      :file.close(fd)
    else
      {:error, reason} ->
        _ = :file.close(fd)
        {:error, reason}
    end
  end

  # The replay carries the jobs, the counter, the highest id the log has ever
  # handed out, and the `next` marker with the line it was read on, so that a
  # counter no higher than an id the log carries is caught whatever order the
  # two lines came in.
  defp replay(bytes) do
    {lines, torn} = split_lines(bytes)

    if torn != "" do
      Logger.warning("jobq: dropping a torn final line of #{byte_size(torn)} bytes")
    end

    lines
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, {%{}, 1, 0, nil}}, fn {line, number}, {:ok, log} ->
      case apply_line(line, log, number) do
        {:ok, log} -> {:cont, {:ok, log}}
        :error -> {:halt, {:error, {:corrupt, number}}}
        {:record, key, rule} -> {:halt, {:error, {:record, key, rule}}}
      end
    end)
    |> finish()
  end

  defp finish({:ok, {jobs, next, seen, marker}}) do
    case marker do
      {line, counter} when counter <= seen -> {:error, {:corrupt, line}}
      _other -> {:ok, {jobs, next}}
    end
  end

  defp finish({:error, reason}), do: {:error, reason}

  defp split_lines(bytes) do
    case String.split(bytes, "\n") do
      [only] -> {[], only}
      parts -> {Enum.drop(parts, -1), List.last(parts)}
    end
  end

  defp apply_line("", log, _number), do: {:ok, log}

  defp apply_line(line, log, number) do
    case Json.decode(line) do
      {:ok, map} when is_map(map) -> apply_record(map, log, number)
      _other -> :error
    end
  end

  defp apply_record(%{"next" => n}, {jobs, next, seen, _marker}, number)
       when is_integer(n) and n > 0,
       do: {:ok, {jobs, max(next, n), seen, {number, n}}}

  defp apply_record(%{"next" => _n}, _log, _number), do: :error

  defp apply_record(%{"deleted" => true, "id" => id}, {jobs, next, seen, marker}, _number) do
    case Job.parse_id(id) do
      {:ok, n} -> {:ok, {Map.delete(jobs, n), max(next, n + 1), max(seen, n), marker}}
      :error -> :error
    end
  end

  defp apply_record(map, {jobs, next, seen, marker}, _number) do
    with :ok <- Job.check_record(map),
         {:ok, job} <- Job.from_record(map) do
      {:ok, {Map.put(jobs, job.n, job), max(next, job.n + 1), max(seen, job.n), marker}}
    else
      {:error, rule} -> {:record, Job.record_key(map), rule}
      :error -> {:record, Job.record_key(map), "the record is not a job"}
    end
  end

  # Server

  @impl GenServer
  def init(opts) do
    ref = Keyword.fetch!(opts, :ref)
    dir = Keyword.fetch!(opts, :dir)
    fault = Keyword.get(opts, :fault, fn _ -> false end)
    path = log_path(dir)

    case :file.open(path, [:append, :raw, :binary]) do
      {:ok, fd} ->
        _ = :file.close(fd)

        {:ok, %{path: path, buffer: [], waiters: [], batch: 0, epoch: 0, ref: ref, fault: fault}}

      {:error, reason} ->
        {:stop, {:open, path, reason}}
    end
  end

  @impl GenServer
  def handle_cast({:commit, _records, from, _reply, epoch}, %{epoch: current} = state)
      when epoch != current do
    refuse(from)
    {:noreply, state}
  end

  def handle_cast({:commit, records, from, reply, _epoch}, state) do
    lines = Enum.map(records, &encode_record/1)

    state = %{
      state
      | buffer: [state.buffer, lines],
        waiters: add_waiter(state.waiters, from, reply)
    }

    if length(state.waiters) >= @max_batch or idle?() do
      {_result, state} = flush(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(:sync, _from, state) do
    {result, state} = flush(state)
    {:reply, result, state}
  end

  def handle_call(:epoch, _from, state), do: {:reply, state.epoch, state}

  @impl GenServer
  def handle_info(:flush, state) do
    {_result, state} = flush(state)
    {:noreply, state}
  end

  defp refuse(nil), do: :ok
  defp refuse(from), do: GenServer.reply(from, {:error, :store})

  defp add_waiter(waiters, nil, _reply), do: waiters
  defp add_waiter(waiters, from, reply), do: [{from, reply} | waiters]

  defp idle?, do: {:message_queue_len, 0} == Process.info(self(), :message_queue_len)

  @spec flush(state()) :: {:ok | {:error, term()}, state()}
  defp flush(%{buffer: []} = state), do: {:ok, state}

  defp flush(state) do
    batch = state.batch + 1
    state = %{state | batch: batch}

    case write(state, batch) do
      :ok ->
        Enum.each(state.waiters, fn {from, reply} -> GenServer.reply(from, reply) end)
        {:ok, %{state | buffer: [], waiters: []}}

      {:error, reason} ->
        {{:error, reason}, fail_batch(state, reason)}
    end
  end

  # A batch that did not reach the disk: a new epoch, the queue told to go back
  # to what the log says before it answers anything else, and only then the
  # waiters told. The order is what keeps a client that is told `503` from
  # being answered its next request off a state the disk never saw.
  defp fail_batch(state, reason) do
    Logger.warning("jobq: cannot write #{state.path}: #{inspect(reason)}")
    epoch = state.epoch + 1

    case Jobq.Registry.whereis(state.ref, :queue) do
      nil -> :ok
      pid -> send(pid, {:store_epoch, epoch})
    end

    Enum.each(state.waiters, fn {from, _reply} -> refuse(from) end)
    %{state | buffer: [], waiters: [], epoch: epoch}
  end

  # Every batch through a file of its own: the `open` is what a folder that
  # cannot be written any more answers, and what it answers again once it can.
  defp write(state, batch) do
    if state.fault.(batch),
      do: {:error, :injected},
      else: append(state.path, state.buffer)
  end

  defp append(path, buffer) do
    case :file.open(path, [:append, :raw, :binary]) do
      {:ok, fd} -> write_and_close(fd, buffer)
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_record({:put, job}), do: [Json.encode(Job.record(job)), ?\n]

  defp encode_record({:delete, id}),
    do: [Json.encode({:obj, [{"id", id}, {"deleted", true}]}), ?\n]

  defp sync_dir(dir) do
    case :file.open(dir, [:read, :raw]) do
      {:ok, fd} ->
        result = :file.sync(fd)
        _ = :file.close(fd)
        result

      {:error, _reason} ->
        # A platform that will not open a directory: the rename is still
        # ordered after the temporary file's own sync.
        :ok
    end
  end
end
