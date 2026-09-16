defmodule Jobq.Store do
  @moduledoc """
  The store: an append-only log of job records, one JSON object per line.

  The process owns the open file. A caller hands it the records of one
  operation together with the reply that operation owes its client; the process
  writes them, `fsync`s, and only then sends the reply. Records that arrive
  while an `fsync` is in flight are written and synced together, so a busy
  service pays one `fsync` for many jobs and no reply is ever sent before its
  own record is on the disk.

  A write or a sync that fails is not papered over: the waiters of that batch
  are told the store is down (the router turns that into a `503`) and the
  process stops, which under the tree's `:rest_for_one` takes the queue with it
  and replays the log into a state the disk agrees with.

  The log's framing is one line per record, `\\n` terminated, under the job's
  id; the last line of a log may be torn by a crash and is dropped on replay, a
  complete line that is not a record is a corrupt log and refuses to open.
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
           fd: :file.io_device(),
           path: String.t(),
           buffer: iodata(),
           waiters: [{GenServer.from(), term()}],
           batch: non_neg_integer(),
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
  """
  @spec commit(ref(), [record()], GenServer.from() | nil, term()) :: :ok
  def commit(ref, records, from, reply) do
    GenServer.cast(Jobq.Registry.via(ref, :store), {:commit, records, from, reply})
  end

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
  torn final line is dropped; a complete line that is not a record is
  `{:error, {:corrupt, line_number}}`.
  """
  @spec read(Path.t()) :: {:ok, log()} | {:error, term()}
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
  and a rename.
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

  defp replay(bytes) do
    {lines, torn} = split_lines(bytes)

    if torn != "" do
      Logger.warning("jobq: dropping a torn final line of #{byte_size(torn)} bytes")
    end

    lines
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, {%{}, 1}}, fn {line, number}, {:ok, log} ->
      case apply_line(line, log) do
        {:ok, log} -> {:cont, {:ok, log}}
        :error -> {:halt, {:error, {:corrupt, number}}}
      end
    end)
  end

  defp split_lines(bytes) do
    case String.split(bytes, "\n") do
      [only] -> {[], only}
      parts -> {Enum.drop(parts, -1), List.last(parts)}
    end
  end

  defp apply_line("", log), do: {:ok, log}

  defp apply_line(line, {jobs, next}) do
    with {:ok, map} when is_map(map) <- Json.decode(line) do
      case map do
        %{"next" => n} when is_integer(n) and n > 0 ->
          {:ok, {jobs, max(next, n)}}

        %{"deleted" => true, "id" => id} ->
          case Job.parse_id(id) do
            {:ok, n} -> {:ok, {Map.delete(jobs, n), max(next, n + 1)}}
            :error -> :error
          end

        _ ->
          case Job.from_record(map) do
            {:ok, job} -> {:ok, {Map.put(jobs, job.n, job), max(next, job.n + 1)}}
            :error -> :error
          end
      end
    else
      _ -> :error
    end
  end

  # Server

  @impl GenServer
  def init(opts) do
    dir = Keyword.fetch!(opts, :dir)
    fault = Keyword.get(opts, :fault, fn _ -> false end)
    path = log_path(dir)

    case :file.open(path, [:append, :raw, :binary]) do
      {:ok, fd} ->
        {:ok, %{fd: fd, path: path, buffer: [], waiters: [], batch: 0, fault: fault}}

      {:error, reason} ->
        {:stop, {:open, path, reason}}
    end
  end

  @impl GenServer
  def handle_cast({:commit, records, from, reply}, state) do
    lines = Enum.map(records, &encode_record/1)

    state = %{
      state
      | buffer: [state.buffer, lines],
        waiters: add_waiter(state.waiters, from, reply)
    }

    if length(state.waiters) >= @max_batch or idle?() do
      flush(state)
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(:sync, _from, state) do
    case flush(state) do
      {:noreply, state} -> {:reply, :ok, state}
      {:stop, reason, state} -> {:stop, reason, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info(:flush, state), do: flush(state)

  @impl GenServer
  def terminate(_reason, state) do
    _ = :file.close(state.fd)
    :ok
  end

  defp add_waiter(waiters, nil, _reply), do: waiters
  defp add_waiter(waiters, from, reply), do: [{from, reply} | waiters]

  defp idle?, do: {:message_queue_len, 0} == Process.info(self(), :message_queue_len)

  @spec flush(state()) :: {:noreply, state()} | {:stop, term(), state()}
  defp flush(%{buffer: []} = state), do: {:noreply, state}

  defp flush(state) do
    batch = state.batch + 1

    case write(state, batch) do
      :ok ->
        Enum.each(state.waiters, fn {from, reply} -> GenServer.reply(from, reply) end)
        {:noreply, %{state | buffer: [], waiters: [], batch: batch}}

      {:error, reason} ->
        Enum.each(state.waiters, fn {from, _reply} -> GenServer.reply(from, {:error, :store}) end)
        {:stop, {:write, state.path, reason}, %{state | buffer: [], waiters: [], batch: batch}}
    end
  end

  defp write(state, batch) do
    if state.fault.(batch) do
      {:error, :injected}
    else
      with :ok <- :file.write(state.fd, state.buffer), do: :file.sync(state.fd)
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
