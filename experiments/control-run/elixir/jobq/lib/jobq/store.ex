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

  A failure that is not a write's is the board's: anything this process did not
  expect while it applied a batch ends it, and `Jobq.Board` starts it again with
  the queue. So does the chaos switch, which fails the N-th write on purpose
  after its record is on the disk and before its reply is sent. A torn final
  line a killed service left behind is cut off when the process starts, so the
  next record begins a line of its own.

  Beside the log is the archive, `jobq.archive`: done and dead jobs that have
  been left alone for longer than the service's `retain_ms`, one record a line
  with the `archived_at` they were moved at, and a tombstone for an archived
  job that was deleted. A move is two writes in one batch, the archive's
  append and then the log's `{"id":...,"archived":true}`, both synced before
  any reply of the batch; a batch that fails or a kill between them leaves the
  job in both files, and an open reads such a job as archived, because an id
  the archive has ever named is never live again. The archive is append-only
  between compactions, a folder with no archive has an empty one, and its torn
  last line is cut and dropped like the log's.

  A queue renamed is one record on the log, `{"rename":from,"to":to}`, which
  the replay applies in order to the jobs it has read so far and to the queue
  of every job the log has sent to the archive; a job created into `from`
  after it stays in `from`. The archive is not rewritten by a rename: an
  archived job's queue is the one the log last gave it, when the log still
  names it, and otherwise the archive's own with every rename on the log
  applied. A compaction folds the renames into the records it writes and
  leaves none: the log first, with an `archived` word carrying the current
  queue of each archived job whose archive record has an old one, and then the
  archive with current names, so a kill between the two rewrites leaves a
  folder that opens with the same names.

  A log the version before change 1 wrote opens with no tool: `Jobq.Job` reads
  the old field names off a record and the store writes only the new ones, so
  a `compact/1` of such a folder leaves no old name behind.
  """

  use GenServer

  require Logger

  alias Jobq.Board
  alias Jobq.Job
  alias Jobq.Json
  alias Jobq.Rename

  @log_name "jobq.log"
  @archive_name "jobq.archive"
  @max_batch 512

  @type ref :: term()
  @type record ::
          {:put, Job.t()}
          | {:delete, String.t()}
          | {:archive, Job.t()}
          | {:archived, String.t()}
          | {:unarchive, String.t()}
          | {:rename, String.t(), String.t()}
  @type jobs :: %{pos_integer() => Job.t()}
  @type log :: {jobs(), pos_integer()}
  @type folder :: %{jobs: jobs(), next: pos_integer(), archived: jobs()}
  @type fault :: (non_neg_integer() -> boolean() | :between)

  @typep state :: %{
           path: String.t(),
           archive_path: String.t(),
           buffer: iodata(),
           archive: iodata(),
           waiters: [{GenServer.from(), term()}],
           pending: non_neg_integer(),
           batch: non_neg_integer(),
           epoch: non_neg_integer(),
           ref: ref(),
           fault: fault(),
           crash: (pos_integer() -> boolean()),
           counters: Board.counters()
         }

  # Client

  @doc """
  Start the writer for `dir`. Options: `:ref`, `:dir`, the service's
  `:counters`, a test `:fault` over batch numbers (`true` fails the batch
  before it is written, `:between` after the archive's append and before the
  log's), and a `:crash` over write numbers, which is the chaos switch.
  """
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

  @doc "The archive's path inside `dir`."
  @spec archive_path(Path.t()) :: Path.t()
  def archive_path(dir), do: Path.join(dir, @archive_name)

  # Reading and compacting, without a process

  @doc """
  Replay `dir`'s log into the live jobs, oldest record last write wins.

  Returns the jobs by id counter and the counter the next id is taken from. A
  torn final line is dropped; a complete line that is not a JSON object is
  `{:error, {:corrupt, line_number}}`, and one that is an object but not a
  well-formed record is `{:error, {:record, key, rule}}`.
  """
  @spec read(Path.t()) :: {:ok, log()} | {:error, term()}
  def read(dir) do
    with {:ok, folder} <- open(dir), do: {:ok, {folder.jobs, folder.next}}
  end

  @doc """
  Read the whole folder: the live jobs, the counter, and the archived jobs.

  A job the archive has ever named is not live, whatever the log says: that
  is a move a kill or a failed batch cut between its two writes. The counter
  is past every id either file carries, and no key names two jobs of a queue.
  A bad archive refuses the folder as a bad log does, with
  `{:corrupt_archive, line_number}` for a line that is not a JSON object.
  """
  @spec open(Path.t()) :: {:ok, folder()} | {:error, term()}
  def open(dir) do
    with {:ok, folder, _as_filed} <- open_folder(dir), do: {:ok, folder}
  end

  # The folder, and the archived jobs under the queue names the archive file
  # gives them, which a compaction compares with the current ones.
  defp open_folder(dir) do
    with {:ok, {as_filed, named}} <- read_archive(dir),
         {:ok, bytes} <- read_file(log_path(dir)),
         {:ok, {live, next, gone, renames}} <- replay(bytes) do
      jobs = Map.drop(live, named)
      highest = named |> Enum.max(fn -> 0 end)
      archived = Map.new(as_filed, fn {n, job} -> {n, current(job, live, gone, renames)} end)

      with :ok <- unique_keys(jobs, archived) do
        {:ok, %{jobs: jobs, next: max(next, highest + 1), archived: archived}, as_filed}
      end
    end
  end

  # An archived job's queue now: the log's, while the log still names the job
  # (a move a kill cut short, or the word the move wrote), and otherwise the
  # archive's with every rename the log carries applied.
  defp current(job, live, gone, renames) do
    queue =
      case {Map.fetch(live, job.n), Map.fetch(gone, job.n)} do
        {{:ok, on_log}, _gone} -> on_log.queue
        {:error, {:ok, queue}} -> queue
        {:error, :error} -> Rename.apply_all(job.queue, renames)
      end

    %{job | queue: queue}
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, :enoent} -> {:ok, ""}
      {:error, reason} -> {:error, {:open, path, reason}}
    end
  end

  # The archive: its jobs by counter, and every counter it has named, a
  # deleted one included.
  defp read_archive(dir) do
    with {:ok, bytes} <- read_file(archive_path(dir)) do
      {lines, _torn} = split_lines(bytes)

      lines
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, {%{}, MapSet.new()}}, &archive_step/2)
      |> case do
        {:ok, {archived, named}} -> {:ok, {archived, MapSet.to_list(named)}}
        error -> error
      end
    end
  end

  defp archive_step({line, number}, {:ok, acc}) do
    case archive_line(line, acc) do
      {:ok, acc} -> {:cont, {:ok, acc}}
      :error -> {:halt, {:error, {:corrupt_archive, number}}}
      {:record, key, rule} -> {:halt, {:error, {:record, key, rule}}}
    end
  end

  defp archive_line("", acc), do: {:ok, acc}

  defp archive_line(line, {archived, named}) do
    case Json.decode(line) do
      {:ok, %{"deleted" => true, "id" => id}} ->
        case Job.parse_id(id) do
          {:ok, n} -> {:ok, {Map.delete(archived, n), MapSet.put(named, n)}}
          :error -> :error
        end

      {:ok, map} when is_map(map) ->
        with :ok <- Job.check_archived(map),
             {:ok, job} <- Job.from_record(map) do
          {:ok, {Map.put(archived, job.n, job), MapSet.put(named, job.n)}}
        else
          {:error, rule} -> {:record, Job.record_key(map), rule}
          :error -> {:record, Job.record_key(map), "the record is not a job"}
        end

      _other ->
        :error
    end
  end

  defp unique_keys(jobs, archived) do
    [jobs, archived]
    |> Enum.flat_map(&Map.values/1)
    |> Enum.filter(& &1.key)
    |> Enum.sort_by(& &1.n)
    |> Enum.reduce_while(MapSet.new(), fn job, seen ->
      if MapSet.member?(seen, {job.queue, job.key}),
        do: {:halt, {:record, Job.id(job), "the key names another job in its queue"}},
        else: {:cont, MapSet.put(seen, {job.queue, job.key})}
    end)
    |> case do
      {:record, key, rule} -> {:error, {:record, key, rule}}
      _seen -> :ok
    end
  end

  @doc """
  Rewrite `dir`'s log to one line per live job, by id, and then its archive to
  one line per archived job that was not deleted, each through a temporary
  file and a rename. A folder that does not open is not rewritten, so a
  compaction writes well-formed records only.

  The log goes first: once it is rewritten it names no archived job, so a kill
  before the archive's rewrite leaves a folder whose deleted archived jobs are
  still tombstones rather than jobs the log would bring back.
  """
  @spec compact(Path.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def compact(dir) do
    with {:ok, %{jobs: jobs, next: next, archived: archived}, as_filed} <- open_folder(dir),
         :ok <- rewrite(dir, log_path(dir), log_lines(jobs, next, renamed(archived, as_filed))),
         :ok <- rewrite(dir, archive_path(dir), job_lines(archived)) do
      {:ok, map_size(jobs)}
    end
  end

  # The archived jobs whose archive record names a queue that has since been
  # renamed, with the name they have now.
  defp renamed(archived, as_filed) do
    archived
    |> Enum.filter(fn {n, job} -> Map.fetch!(as_filed, n).queue != job.queue end)
    |> Enum.sort_by(fn {n, _job} -> n end)
  end

  defp log_lines(jobs, next, renamed) do
    highest = jobs |> Map.keys() |> Enum.max(fn -> 0 end)

    marker =
      if next > highest + 1,
        do: [[Json.encode({:obj, [{"next", next}]}), ?\n]],
        else: []

    words =
      Enum.map(renamed, fn {_n, job} ->
        [
          Json.encode({:obj, [{"id", Job.id(job)}, {"archived", true}, {"queue", job.queue}]}),
          ?\n
        ]
      end)

    marker ++ words ++ job_lines(jobs)
  end

  defp job_lines(jobs) do
    jobs
    |> Enum.sort_by(fn {n, _job} -> n end)
    |> Enum.map(fn {_n, job} -> [Json.encode(Job.record(job)), ?\n] end)
  end

  defp rewrite(dir, path, lines) do
    tmp = path <> ".compact"

    with {:ok, fd} <- :file.open(tmp, [:write, :raw, :binary]),
         :ok <- write_and_close(fd, lines),
         :ok <- :file.rename(tmp, path),
         :ok <- sync_dir(dir) do
      :ok
    else
      {:error, reason} ->
        _ = File.rm(tmp)
        {:error, {:compact, reason}}
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
  # handed out, the `next` marker with the line it was read on, the queue of
  # every job the log sent to the archive, and the renames, latest first. A marker is
  # refused when it is no higher than an id written before it; the ids after it
  # are the ones a compaction kept, which are below it, and the ones created
  # since, which start at it. A compaction never writes a counter of 1.
  defp replay(bytes) do
    {lines, torn} = split_lines(bytes)

    if torn != "" do
      Logger.warning("jobq: dropping a torn final line of #{byte_size(torn)} bytes")
    end

    lines
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, {%{}, 1, 0, nil, %{}, []}}, fn {line, number}, {:ok, log} ->
      case apply_line(line, log, number) do
        {:ok, log} -> {:cont, {:ok, log}}
        :error -> {:halt, {:error, {:corrupt, number}}}
        {:record, key, rule} -> {:halt, {:error, {:record, key, rule}}}
      end
    end)
    |> finish()
  end

  defp finish({:ok, {jobs, next, _seen, _marker, gone, renames}}),
    do: {:ok, {jobs, next, gone, Enum.reverse(renames)}}

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

  defp apply_record(%{"next" => n}, {jobs, next, seen, _marker, gone, renames}, number)
       when is_integer(n) and n > 1 and n > seen,
       do: {:ok, {jobs, max(next, n), seen, {number, n}, gone, renames}}

  defp apply_record(%{"next" => _n}, _log, _number), do: :error

  defp apply_record(%{"rename" => _from} = map, log, _number) do
    {jobs, next, seen, marker, gone, renames} = log

    with :ok <- Rename.check_record(map),
         %{"rename" => from, "to" => to} = map,
         :ok <- target_empty(jobs, to) do
      {moved, _count} = Rename.jobs(jobs, from, to)
      gone = Map.new(gone, fn {n, queue} -> {n, Rename.apply_name(queue, from, to)} end)
      {:ok, {moved, next, seen, marker, gone, [{from, to} | renames]}}
    else
      {:error, rule} -> {:record, "rename " <> inspect(map["rename"]), rule}
    end
  end

  # The word a move writes, or the one a compaction writes with the queue the
  # job has now: either way the job is off the board.
  defp apply_record(%{"archived" => true, "id" => id} = map, log, number) do
    with {:ok, n} <- Job.parse_id(id),
         {:ok, queue} <- gone_queue(map, log, n),
         {:ok, {jobs, next, seen, marker, gone, renames}} <-
           apply_record(%{"deleted" => true, "id" => id}, log, number) do
      gone = if queue, do: Map.put(gone, n, queue), else: gone
      {:ok, {jobs, next, seen, marker, gone, renames}}
    else
      {:record, key, rule} -> {:record, key, rule}
      _error -> :error
    end
  end

  defp apply_record(%{"deleted" => true, "id" => id}, log, _number) do
    {jobs, next, seen, marker, gone, renames} = log

    case Job.parse_id(id) do
      {:ok, n} ->
        {:ok,
         {Map.delete(jobs, n), max(next, n + 1), max(seen, n), marker, Map.delete(gone, n),
          renames}}

      :error ->
        :error
    end
  end

  defp apply_record(map, {jobs, next, seen, marker, gone, renames}, _number) do
    with :ok <- Job.check_record(map),
         {:ok, job} <- Job.from_record(map) do
      {:ok,
       {Map.put(jobs, job.n, job), max(next, job.n + 1), max(seen, job.n), marker, gone, renames}}
    else
      {:error, rule} -> {:record, Job.record_key(map), rule}
      :error -> {:record, Job.record_key(map), "the record is not a job"}
    end
  end

  # A rename's target has no job on the log's board at that point: the service
  # never merges two queues, so a record that would is not one it wrote.
  defp target_empty(jobs, to) do
    if Enum.any?(jobs, fn {_n, job} -> job.queue == to end),
      do: {:error, "a rename's target has no job"},
      else: :ok
  end

  # The queue an archived job had when the log sent it off: the one the word
  # carries, or the job's on the log.
  defp gone_queue(%{"queue" => queue} = map, _log, _n) do
    case Job.queue(queue) do
      {:ok, queue} -> {:ok, queue}
      {:error, rule} -> {:record, Job.record_key(map), rule}
    end
  end

  defp gone_queue(_map, {jobs, _next, _seen, _marker, gone, _renames}, n) do
    case Map.fetch(jobs, n) do
      {:ok, job} -> {:ok, job.queue}
      :error -> {:ok, Map.get(gone, n)}
    end
  end

  # Server

  @impl GenServer
  def init(opts) do
    ref = Keyword.fetch!(opts, :ref)
    dir = Keyword.fetch!(opts, :dir)
    counters = Keyword.get_lazy(opts, :counters, &Board.counters/0)
    path = log_path(dir)

    case open_both(path, archive_path(dir)) do
      :ok ->
        Board.started(counters)

        {:ok,
         %{
           path: path,
           archive_path: archive_path(dir),
           buffer: [],
           archive: [],
           waiters: [],
           pending: 0,
           batch: 0,
           epoch: 0,
           ref: ref,
           fault: Keyword.get(opts, :fault, fn _ -> false end),
           crash: Keyword.get(opts, :crash, fn _ -> false end),
           counters: counters
         }}

      {:error, {file, reason}} ->
        {:stop, {:open, file, reason}}
    end
  end

  defp open_both(path, archive) do
    with {:log, :ok} <- {:log, open_log(path)},
         {:archive, :ok} <- {:archive, open_log(archive)} do
      :ok
    else
      {:log, {:error, reason}} -> {:error, {path, reason}}
      {:archive, {:error, reason}} -> {:error, {archive, reason}}
    end
  end

  # The log as the writer needs it: there, and ending at a line's end.
  defp open_log(path) do
    case :file.open(path, [:read, :append, :raw, :binary]) do
      {:ok, fd} ->
        result = cut_torn(fd)
        _ = :file.close(fd)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cut_torn(fd) do
    with {:ok, size} <- :file.position(fd, :eof),
         {:ok, keep} <- line_end(fd, size, size) do
      cut_at(fd, keep, size)
    end
  end

  defp cut_at(_fd, size, size), do: :ok

  defp cut_at(fd, keep, size) do
    Logger.warning("jobq: cutting a torn final line of #{size - keep} bytes")

    with {:ok, _position} <- :file.position(fd, keep),
         :ok <- :file.truncate(fd) do
      :file.sync(fd)
    end
  end

  # The offset just past the last `\n` at or before `upto`, read backwards in
  # chunks; 0 when the log has no complete line.
  @chunk 65_536
  defp line_end(_fd, 0, _size), do: {:ok, 0}

  defp line_end(fd, upto, size) do
    from = max(upto - @chunk, 0)

    case :file.pread(fd, from, upto - from) do
      {:ok, bytes} ->
        case :binary.matches(bytes, "\n") do
          [] ->
            line_end(fd, from, size)

          matches ->
            {at, 1} = List.last(matches)
            {:ok, from + at + 1}
        end

      :eof ->
        {:ok, 0}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A crash report names the batch, not its records: the payloads are the
  # clients' and a full buffer is hundreds of them.
  @impl GenServer
  def format_status(status) do
    Map.update(status, :state, nil, fn
      %{buffer: _} = state ->
        %{state | buffer: :redacted, archive: :redacted, waiters: length(state.waiters)}

      other ->
        other
    end)
    |> Map.update(:message, nil, &redact_message/1)
  end

  defp redact_message({:"$gen_cast", {:commit, records, _from, _reply, epoch}}),
    do: {:"$gen_cast", {:commit, {length(records), :records}, epoch}}

  defp redact_message(message), do: message

  @impl GenServer
  def handle_cast({:commit, _records, from, _reply, epoch}, %{epoch: current} = state)
      when epoch != current do
    refuse(from)
    {:noreply, state}
  end

  def handle_cast({:commit, records, from, reply, _epoch}, state) do
    {archive, log} = Enum.split_with(records, &archive_record?/1)

    state = %{
      state
      | buffer: append_lines(state.buffer, log),
        archive: append_lines(state.archive, archive),
        waiters: add_waiter(state.waiters, from, reply),
        pending: state.pending + length(records)
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

  defp archive_record?({kind, _value}), do: kind in [:archive, :unarchive]
  defp archive_record?(_record), do: false

  defp append_lines(buffer, []), do: buffer
  defp append_lines(buffer, records), do: [buffer, Enum.map(records, &encode_record/1)]

  defp refuse(nil), do: :ok
  defp refuse(from), do: GenServer.reply(from, {:error, :store})

  defp add_waiter(waiters, nil, _reply), do: waiters
  defp add_waiter(waiters, from, reply), do: [{from, reply} | waiters]

  defp idle?, do: {:message_queue_len, 0} == Process.info(self(), :message_queue_len)

  @spec flush(state()) :: {:ok | {:error, term()}, state()}
  defp flush(%{buffer: [], archive: []} = state), do: {:ok, state}

  defp flush(state) do
    batch = state.batch + 1
    state = %{state | batch: batch}

    case write(state, batch) do
      :ok ->
        chaos(state)
        Enum.each(state.waiters, fn {from, reply} -> GenServer.reply(from, reply) end)
        {:ok, %{state | buffer: [], archive: [], waiters: [], pending: 0}}

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
    %{state | buffer: [], archive: [], waiters: [], pending: 0, epoch: epoch}
  end

  # The chaos switch: the batch is on the disk, its replies are not sent, and
  # if one of its writes is one the switch fails, the board fails here, as an
  # unexpected error at this point would.
  defp chaos(state) do
    {before, total} = Board.applied(state.counters, state.pending)

    if total > before and Enum.any?((before + 1)..total, state.crash) do
      exit({:chaos, total})
    end

    :ok
  end

  # Every batch through a file of its own: the `open` is what a folder that
  # cannot be written any more answers, and what it answers again once it can.
  # The archive's lines are on the disk before the log's.
  defp write(state, batch) do
    case state.fault.(batch) do
      :between ->
        with :ok <- append(state.archive_path, state.archive), do: {:error, :injected}

      true ->
        {:error, :injected}

      false ->
        with :ok <- append(state.archive_path, state.archive),
             do: append(state.path, state.buffer)
    end
  end

  defp append(_path, []), do: :ok

  defp append(path, buffer) do
    case :file.open(path, [:append, :raw, :binary]) do
      {:ok, fd} -> write_and_close(fd, buffer)
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_record({:put, job}), do: [Json.encode(Job.record(job)), ?\n]

  defp encode_record({:delete, id}),
    do: [Json.encode({:obj, [{"id", id}, {"deleted", true}]}), ?\n]

  defp encode_record({:archive, job}), do: [Json.encode(Job.record(job)), ?\n]

  defp encode_record({:archived, id}),
    do: [Json.encode({:obj, [{"id", id}, {"archived", true}]}), ?\n]

  defp encode_record({:unarchive, id}), do: encode_record({:delete, id})

  defp encode_record({:rename, from, to}),
    do: [Json.encode({:obj, [{"rename", from}, {"to", to}]}), ?\n]

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
