defmodule Jobq.Router do
  @moduledoc """
  The routes, the token, and the shape of a request body.

  Everything the API rejects before the queue sees it is here: a missing or
  empty bearer token is `401`, a method a route does not have is `405`, an
  unknown route is `404`, and a body that is not JSON, is missing a field, has
  a field of the wrong shape, or carries a field the route does not know is
  `400`. `/health` is the one route that takes no token.

  Nothing that goes wrong inside a request leaves this function by any door but
  its own: a queue that is down or too slow, and anything the implementation
  did not expect, are `503` with the connection and the next request untouched.
  """

  require Logger

  alias Jobq.Job
  alias Jobq.Json
  alias Jobq.Queue

  @type request :: %{
          required(:method) => String.t(),
          required(:path) => String.t(),
          required(:headers) => %{String.t() => String.t()},
          required(:body) => binary(),
          optional(:version) => term()
        }

  @doc "Answer one request: a status and the JSON body, or `nil` for no body."
  @spec route(request(), Queue.ref()) :: {100..599, iodata() | nil}
  def route(request, ref) do
    {path, query} = split_target(request.path)
    segments = segments(path)

    case dispatch(request, ref, segments, query) do
      {status, nil} -> {status, nil}
      {status, body} -> {status, Json.encode(body)}
    end
  rescue
    error ->
      Logger.error("jobq: #{request.method} #{request.path}: " <> Exception.message(error))
      unavailable()
  catch
    kind, reason ->
      Logger.error("jobq: #{request.method} #{request.path}: #{inspect(kind)} #{inspect(reason)}")
      unavailable()
  end

  defp unavailable,
    do: {503, Json.encode(error("the service could not complete this request"))}

  defp dispatch(%{method: "GET"}, ref, ["health"], _query), do: reply(Queue.health(ref))
  defp dispatch(_request, _ref, ["health"], _query), do: {405, error("method not allowed")}

  defp dispatch(request, ref, segments, query) do
    case token(request) do
      {:ok, token} -> authorized(request, ref, segments, query, token)
      :error -> {401, error("a bearer token is required")}
    end
  end

  defp authorized(request, ref, ["queues"], _query, _token) do
    case request.method do
      "GET" -> reply(Queue.queues(ref))
      _other -> {405, error("method not allowed")}
    end
  end

  defp authorized(request, ref, ["jobs"], query, _token) do
    case request.method do
      "POST" -> create(request, ref)
      "GET" -> list(ref, query)
      _other -> {405, error("method not allowed")}
    end
  end

  defp authorized(request, ref, ["jobs", id], _query, _token) do
    case request.method do
      "GET" -> reply(Queue.get(ref, id))
      "DELETE" -> reply(Queue.delete(ref, id))
      _other -> {405, error("method not allowed")}
    end
  end

  defp authorized(%{method: "POST"} = request, ref, ["jobs", id, "ack"], _query, token) do
    case fields(request.body, [], []) do
      {:ok, _fields} -> reply(Queue.ack(ref, id, token))
      {:error, message} -> {400, error(message)}
    end
  end

  defp authorized(%{method: "POST"} = request, ref, ["jobs", id, "retry"], _query, _token) do
    case fields(request.body, [], []) do
      {:ok, _fields} -> reply(Queue.retry(ref, id))
      {:error, message} -> {400, error(message)}
    end
  end

  defp authorized(%{method: "POST"} = request, ref, ["jobs", id, "fail"], _query, token) do
    with {:ok, fields} <- fields(request.body, [], ["reason"]),
         {:ok, reason} <- optional(fields, "reason", nil, &Job.reason/1) do
      reply(Queue.fail(ref, id, token, reason))
    else
      {:error, message} -> {400, error(message)}
    end
  end

  defp authorized(%{method: "POST"} = request, ref, ["jobs", id, "handoff"], _query, token) do
    with {:ok, fields} <- fields(request.body, ["to"], []),
         {:ok, to} <- Job.worker(fields["to"]) do
      reply(Queue.handoff(ref, id, token, to))
    else
      {:error, message} -> {400, error(message)}
    end
  end

  defp authorized(%{method: "POST"} = request, ref, ["queues", queue, "rename"], _query, _token) do
    with {:ok, queue} <- Job.queue(queue),
         {:ok, fields} <- fields(request.body, ["to"], []),
         {:ok, to} <- Job.queue(fields["to"]) do
      reply(Queue.rename(ref, queue, to))
    else
      {:error, message} -> {400, error(message)}
    end
  end

  defp authorized(%{method: "POST"} = request, ref, ["queues", queue, "lease"], _query, token) do
    with {:ok, queue} <- Job.queue(queue),
         {:ok, fields} <- fields(request.body, [], ["lease_ms"]),
         {:ok, lease_ms} <- optional(fields, "lease_ms", 30_000, &Job.lease_ms/1) do
      reply(Queue.lease(ref, queue, lease_ms, token))
    else
      {:error, message} -> {400, error(message)}
    end
  end

  defp authorized(_request, _ref, segments, _query, _token) do
    if known_route?(segments),
      do: {405, error("method not allowed")},
      else: {404, error("no such route")}
  end

  defp known_route?(["jobs", _id, suffix]) when suffix in ["ack", "fail", "retry", "handoff"],
    do: true

  defp known_route?(["queues", _queue, suffix]) when suffix in ["lease", "rename"], do: true
  defp known_route?(_segments), do: false

  defp create(request, ref) do
    with {:ok, fields} <-
           fields(request.body, ["queue", "payload", "max_tries"], [
             "delay_ms",
             "backoff_ms",
             "key"
           ]),
         {:ok, queue} <- Job.queue(fields["queue"]),
         {:ok, payload} <- Job.payload(fields["payload"]),
         {:ok, max_tries} <- Job.max_tries(fields["max_tries"]),
         {:ok, delay_ms} <- optional(fields, "delay_ms", 0, &Job.delay_ms/1),
         {:ok, backoff_ms} <- optional(fields, "backoff_ms", 0, &Job.backoff_ms/1),
         {:ok, key} <- optional(fields, "key", nil, &Job.key/1) do
      reply(Queue.create(ref, queue, payload, max_tries, delay_ms, backoff_ms, key))
    else
      {:error, message} -> {400, error(message)}
    end
  end

  defp list(ref, query) do
    with {:ok, params} <- query_params(query),
         {:ok, queue} <- filter(params, "queue", &Job.queue/1),
         {:ok, state} <- filter(params, "state", &parse_state/1),
         {:ok, key} <- filter(params, "key", &Job.key/1),
         :ok <- key_needs_queue(key, queue) do
      reply(Queue.list(ref, queue, state, key))
    else
      {:error, message} -> {400, error(message)}
    end
  end

  defp key_needs_queue(key, nil) when is_binary(key), do: {:error, "key needs a queue"}
  defp key_needs_queue(_key, _queue), do: :ok

  defp parse_state(name) do
    case Job.parse_state(name) do
      {:ok, state} -> {:ok, state}
      :error -> {:error, "state must be " <> state_list()}
    end
  end

  defp state_list do
    {last, rest} = List.pop_at(Job.state_names(), -1)
    Enum.join(rest, ", ") <> " or " <> last
  end

  defp filter(params, name, check) do
    case Map.fetch(params, name) do
      :error -> {:ok, nil}
      {:ok, value} -> check.(value)
    end
  end

  defp query_params(""), do: {:ok, %{}}

  defp query_params(query) do
    params = URI.decode_query(query)

    case Map.keys(params) -- ["queue", "state", "key"] do
      [] -> {:ok, params}
      [unknown | _rest] -> {:error, "unknown query parameter '#{unknown}'"}
    end
  end

  @spec reply(Queue.reply()) :: {100..599, Json.value() | nil}
  defp reply({:error, :store}), do: {503, error("the store is not accepting writes")}
  defp reply({status, body}), do: {status, body}

  defp error(message), do: {:obj, [{"error", message}]}

  # The body: JSON, an object, every required field present, no field the
  # route does not know.

  defp fields(body, required, optional) do
    with {:ok, map} <- decode_object(body),
         :ok <- require_fields(map, required),
         :ok <- reject_unknown(map, required ++ optional) do
      {:ok, map}
    end
  end

  defp decode_object(""), do: {:ok, %{}}

  defp decode_object(body) do
    case Json.decode(body) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _other} -> {:error, "the body must be a JSON object"}
      {:error, _reason} -> {:error, "the body must be JSON"}
    end
  end

  defp require_fields(map, required) do
    case Enum.find(required, fn name -> not Map.has_key?(map, name) end) do
      nil -> :ok
      name -> {:error, "'#{name}' is required"}
    end
  end

  defp reject_unknown(map, known) do
    case Map.keys(map) -- known do
      [] -> :ok
      [name | _rest] -> {:error, "unknown field '#{name}'"}
    end
  end

  defp optional(fields, name, default, check) do
    case Map.fetch(fields, name) do
      :error -> {:ok, default}
      {:ok, value} -> check.(value)
    end
  end

  # The token: `authorization: Bearer <token>`, and the token names the worker.

  defp token(request) do
    case Map.fetch(request.headers, "authorization") do
      {:ok, value} -> bearer(value)
      :error -> :error
    end
  end

  defp bearer(value) do
    with [scheme, rest] <- String.split(value, " ", parts: 2),
         "bearer" <- String.downcase(scheme, :ascii),
         token when token != "" <- String.trim(rest) do
      {:ok, token}
    else
      _ -> :error
    end
  end

  defp split_target(target) do
    case String.split(target, "?", parts: 2) do
      [path] -> {path, ""}
      [path, query] -> {path, query}
    end
  end

  defp segments(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.map(&URI.decode_www_form/1)
  end
end
