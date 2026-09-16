defmodule Jobq.ApiTest do
  use ExUnit.Case, async: true

  alias Jobq.Test.Api
  alias Jobq.Test.Clock
  alias Jobq.Test.Service

  setup do
    Service.start(sweep_ms: 50)
  end

  describe "the token" do
    test "every route but /health wants a bearer token", %{port: port} do
      assert {200, %{"queued" => 0}} = Api.request(port, "", "GET", "/health")

      for {method, path} <- [
            {"POST", "/jobs"},
            {"GET", "/jobs"},
            {"GET", "/jobs/j_1"},
            {"DELETE", "/jobs/j_1"},
            {"POST", "/jobs/j_1/ack"},
            {"POST", "/jobs/j_1/fail"},
            {"POST", "/jobs/j_1/retry"},
            {"POST", "/queues/emails/lease"}
          ] do
        assert {401, %{"error" => _why}} = raw_without_token(port, method, path)
      end
    end

    test "a token that is empty, or not a bearer, is 401", %{port: port} do
      assert String.starts_with?(
               Api.raw(
                 port,
                 "GET /jobs HTTP/1.1\r\nconnection: close\r\nauthorization: Bearer \r\n\r\n"
               ),
               "HTTP/1.1 401"
             )

      assert String.starts_with?(
               Api.raw(
                 port,
                 "GET /jobs HTTP/1.1\r\nconnection: close\r\nauthorization: Basic abc\r\n\r\n"
               ),
               "HTTP/1.1 401"
             )
    end

    test "the token names the worker on a lease", %{port: port} do
      assert {201, _job} = create(port)

      assert {200, %{"worker" => "bob"}} =
               Api.request(port, "bob", "POST", "/queues/emails/lease")
    end
  end

  describe "the routes" do
    test "a method a route does not have is 405", %{port: port} do
      assert {405, _error} = Api.request(port, "alice", "PUT", "/jobs")
      assert {405, _error} = Api.request(port, "alice", "POST", "/jobs/j_1")
      assert {405, _error} = Api.request(port, "alice", "GET", "/jobs/j_1/ack")
      assert {405, _error} = Api.request(port, "alice", "PUT", "/jobs/j_1/retry")
      assert {405, _error} = Api.request(port, "alice", "GET", "/queues/emails/lease")
      assert {405, _error} = Api.request(port, "alice", "POST", "/health")
      assert {405, _error} = Api.request(port, "alice", "POST", "/queues")
    end

    test "a route that is not there is 404", %{port: port} do
      assert {404, _error} = Api.request(port, "alice", "GET", "/")
      assert {404, _error} = Api.request(port, "alice", "GET", "/jobs/j_1/nope")
      assert {404, _error} = Api.request(port, "alice", "GET", "/health/extra")
    end
  end

  describe "POST /jobs" do
    test "creates a job and answers 201 with it", %{port: port} do
      assert {201, job} =
               create(port, %{"queue" => "emails", "payload" => "hi", "max_tries" => 3})

      assert %{
               "id" => "j_1",
               "queue" => "emails",
               "state" => "queued",
               "payload" => "hi",
               "tries" => 0,
               "max_tries" => 3,
               "backoff_ms" => 0,
               "created_at" => created,
               "updated_at" => created
             } = job

      assert {:ok, _datetime, 0} = DateTime.from_iso8601(created)
      refute Map.has_key?(job, "worker")
      refute Map.has_key?(job, "reason")
      refute Map.has_key?(job, "run_at")
    end

    test "a delay makes the job scheduled, and a backoff is kept on it", %{port: port} do
      assert {201, job} =
               create(port, %{
                 "queue" => "emails",
                 "payload" => "hi",
                 "max_tries" => 3,
                 "delay_ms" => 60_000,
                 "backoff_ms" => 5_000
               })

      assert %{"state" => "scheduled", "backoff_ms" => 5_000, "run_at" => run_at} = job
      assert {:ok, _datetime, 0} = DateTime.from_iso8601(run_at)
      refute Map.has_key?(job, "delay_ms")

      assert {204, nil} = Api.request(port, "bob", "POST", "/queues/emails/lease")

      assert {201, plain} =
               create(port, %{
                 "queue" => "emails",
                 "payload" => "hi",
                 "max_tries" => 3,
                 "delay_ms" => 0
               })

      assert %{"state" => "queued", "backoff_ms" => 0} = plain
    end

    test "a delay_ms or a backoff_ms out of range, or not an integer, is 400", %{port: port} do
      for field <- ["delay_ms", "backoff_ms"] do
        for value <- [-1, 86_400_001, "soon", 1.5, nil] do
          body =
            %{"queue" => "e", "payload" => "hi", "max_tries" => 1}
            |> Map.put(field, value)

          assert {400, %{"error" => _why}} = create(port, body)
        end
      end

      # 86,400,000 is a delay and not a backoff: a backoff stops at an hour.
      assert {201, _job} =
               create(port, %{
                 "queue" => "e",
                 "payload" => "hi",
                 "max_tries" => 1,
                 "delay_ms" => 86_400_000
               })

      assert {400, _error} =
               create(port, %{
                 "queue" => "e",
                 "payload" => "hi",
                 "max_tries" => 1,
                 "backoff_ms" => 3_600_001
               })
    end

    test "a request that still says attempts or max_attempts is 400", %{port: port} do
      assert {400, %{"error" => _why}} =
               create(port, %{"queue" => "e", "payload" => "hi", "max_attempts" => 1})

      assert {400, _error} =
               create(port, %{
                 "queue" => "e",
                 "payload" => "hi",
                 "max_tries" => 1,
                 "attempts" => 0
               })
    end

    test "a body that is not JSON, or not an object, is 400", %{port: port} do
      assert {400, %{"error" => _why}} = Api.request(port, "alice", "POST", "/jobs", "{")
      assert {400, _error} = Api.request(port, "alice", "POST", "/jobs", "[1,2]")
      assert {400, _error} = Api.request(port, "alice", "POST", "/jobs", ~s({"queue":"q"} junk))
    end

    test "a missing field, an unknown field, or a field of the wrong shape is 400", %{port: port} do
      assert {400, _error} =
               Api.request(port, "alice", "POST", "/jobs", ~s({"payload":"hi","max_tries":1}))

      assert {400, _error} =
               Api.request(port, "alice", "POST", "/jobs", ~s({"queue":"q","max_tries":1}))

      assert {400, _error} =
               Api.request(port, "alice", "POST", "/jobs", ~s({"queue":"q","payload":"hi"}))

      assert {400, _error} =
               create(port, %{
                 "queue" => "e",
                 "payload" => "hi",
                 "max_tries" => 1,
                 "extra" => 1
               })

      assert {400, _error} =
               create(port, %{"queue" => "", "payload" => "hi", "max_tries" => 1})

      assert {400, _error} =
               create(port, %{"queue" => "a b", "payload" => "hi", "max_tries" => 1})

      assert {400, _error} = create(port, %{"queue" => "e", "payload" => 7, "max_tries" => 1})

      assert {400, _error} =
               create(port, %{"queue" => "e", "payload" => "hi", "max_tries" => 0})

      assert {400, _error} =
               create(port, %{"queue" => "e", "payload" => "hi", "max_tries" => 101})

      assert {400, _error} =
               create(port, %{"queue" => "e", "payload" => "hi", "max_tries" => "3"})

      assert {400, _error} =
               create(port, %{"queue" => "e", "payload" => "a\tb", "max_tries" => 3})
    end

    test "a payload of 60 KiB is taken and one byte more is not", %{port: port} do
      assert {201, _job} =
               create(port, %{
                 "queue" => "e",
                 "payload" => String.duplicate("x", 61_440),
                 "max_tries" => 1
               })

      assert {400, _error} =
               create(port, %{
                 "queue" => "e",
                 "payload" => String.duplicate("x", 61_441),
                 "max_tries" => 1
               })
    end
  end

  describe "GET /jobs" do
    test "filters by queue and by state", %{port: port} do
      assert {201, _job} =
               create(port, %{"queue" => "a", "payload" => "one", "max_tries" => 1})

      assert {201, _job} =
               create(port, %{"queue" => "b", "payload" => "two", "max_tries" => 1})

      assert {200, _job} = Api.request(port, "bob", "POST", "/queues/b/lease")

      assert {200, %{"jobs" => [%{"id" => "j_1"}, %{"id" => "j_2"}]}} =
               Api.request(port, "alice", "GET", "/jobs")

      assert {200, %{"jobs" => [%{"id" => "j_1"}]}} =
               Api.request(port, "alice", "GET", "/jobs?queue=a")

      assert {200, %{"jobs" => [%{"id" => "j_2"}]}} =
               Api.request(port, "alice", "GET", "/jobs?state=leased")

      assert {200, %{"jobs" => []}} =
               Api.request(port, "alice", "GET", "/jobs?queue=a&state=done")
    end

    test "a filter that is not a queue name or a state is 400", %{port: port} do
      assert {400, _error} = Api.request(port, "alice", "GET", "/jobs?state=sideways")
      assert {400, _error} = Api.request(port, "alice", "GET", "/jobs?queue=a%20b")
      assert {400, _error} = Api.request(port, "alice", "GET", "/jobs?limit=5")
    end

    test "state=scheduled is a filter of its own", %{port: port} do
      assert {201, _job} =
               create(port, %{
                 "queue" => "a",
                 "payload" => "later",
                 "max_tries" => 1,
                 "delay_ms" => 60_000
               })

      assert {201, _job} = create(port, %{"queue" => "a", "payload" => "now", "max_tries" => 1})

      assert {200, %{"jobs" => [%{"id" => "j_1", "state" => "scheduled"}]}} =
               Api.request(port, "alice", "GET", "/jobs?state=scheduled")

      assert {200, %{"jobs" => [%{"id" => "j_2"}]}} =
               Api.request(port, "alice", "GET", "/jobs?state=queued")
    end
  end

  describe "POST /jobs/{id}/retry" do
    test "a dead job goes back to its queue, and anything else is 409", %{
      port: port,
      clock: clock
    } do
      assert {201, _job} =
               create(port, %{"queue" => "emails", "payload" => "hi", "max_tries" => 1})

      assert {200, _job} = Api.request(port, "bob", "POST", "/queues/emails/lease")
      assert {409, _error} = Api.request(port, "alice", "POST", "/jobs/j_1/retry")

      assert {200, %{"state" => "dead"}} =
               Api.request(port, "bob", "POST", "/jobs/j_1/fail", ~s({"reason":"boom"}))

      assert {200, job} = Api.request(port, "alice", "POST", "/jobs/j_1/retry")
      assert %{"state" => "queued", "tries" => 0} = job
      refute Map.has_key?(job, "reason")

      assert {409, _error} = Api.request(port, "alice", "POST", "/jobs/j_1/retry")
      assert {404, _error} = Api.request(port, "alice", "POST", "/jobs/j_9/retry")

      Clock.advance(clock, 1)
      assert {200, %{"tries" => 1}} = Api.request(port, "eve", "POST", "/queues/emails/lease")
    end

    test "it needs no body, and refuses one it does not know", %{port: port} do
      assert {201, _job} =
               create(port, %{"queue" => "emails", "payload" => "hi", "max_tries" => 1})

      assert {409, _error} = Api.request(port, "alice", "POST", "/jobs/j_1/retry", "")
      assert {400, _error} = Api.request(port, "alice", "POST", "/jobs/j_1/retry", ~s({"why":1}))
    end
  end

  describe "GET /health" do
    test "counts the scheduled jobs of their own", %{port: port, clock: clock} do
      assert {200, %{"queued" => 0, "scheduled" => 0, "leased" => 0, "done" => 0, "dead" => 0}} =
               Api.request(port, "", "GET", "/health")

      assert {201, _job} =
               create(port, %{
                 "queue" => "emails",
                 "payload" => "hi",
                 "max_tries" => 1,
                 "delay_ms" => 1_000
               })

      assert {200, %{"queued" => 0, "scheduled" => 1}} = Api.request(port, "", "GET", "/health")

      Clock.advance(clock, 1_000)
      assert {200, %{"queued" => 1, "scheduled" => 0}} = Api.request(port, "", "GET", "/health")
    end
  end

  describe "GET /queues" do
    test "an empty service has no queue", %{port: port} do
      assert {200, %{"queues" => []}} = Api.request(port, "alice", "GET", "/queues")
      assert {401, _error} = Api.request(port, "", "GET", "/queues")
    end

    test "every queue with a job, by name, with its counts per state", %{port: port} do
      for queue <- ["reports", "emails", "digests"] do
        assert {201, _job} =
                 create(port, %{"queue" => queue, "payload" => "hi", "max_tries" => 2})
      end

      assert {201, _job} =
               create(port, %{"queue" => "emails", "payload" => "second", "max_tries" => 1})

      assert {200, leased} = Api.request(port, "bob", "POST", "/queues/emails/lease")
      assert {200, _done} = Api.request(port, "bob", "POST", "/jobs/#{leased["id"]}/ack")

      assert {200, %{"queues" => queues}} = Api.request(port, "alice", "GET", "/queues")

      assert queues == [
               %{
                 "name" => "digests",
                 "queued" => 1,
                 "scheduled" => 0,
                 "leased" => 0,
                 "done" => 0,
                 "dead" => 0
               },
               %{
                 "name" => "emails",
                 "queued" => 1,
                 "scheduled" => 0,
                 "leased" => 0,
                 "done" => 1,
                 "dead" => 0
               },
               %{
                 "name" => "reports",
                 "queued" => 1,
                 "scheduled" => 0,
                 "leased" => 0,
                 "done" => 0,
                 "dead" => 0
               }
             ]

      # /health's totals are the sums of the rows.
      assert {200, health} = Api.request(port, "", "GET", "/health")

      for state <- ["queued", "scheduled", "leased", "done", "dead"] do
        assert health[state] == queues |> Enum.map(& &1[state]) |> Enum.sum()
      end
    end

    test "a queue whose last job is deleted leaves the list", %{port: port} do
      assert {201, job} =
               create(port, %{"queue" => "only", "payload" => "hi", "max_tries" => 1})

      assert {200, %{"queues" => [%{"name" => "only"}]}} =
               Api.request(port, "alice", "GET", "/queues")

      assert {204, nil} = Api.request(port, "alice", "DELETE", "/jobs/#{job["id"]}")
      assert {200, %{"queues" => []}} = Api.request(port, "alice", "GET", "/queues")
    end
  end

  describe "a failure inside a request" do
    test "a store that cannot be written is 503, and the next request is answered" do
      # The first batch of the run does not reach the disk.
      %{port: port} = Service.start(sweep_ms: 50, fault: fn batch -> batch == 1 end)

      assert {200, before} = Api.request(port, "", "GET", "/health")
      assert {503, %{"error" => _message}} = create(port)

      # Nothing moved, and the id the refused create took is free again.
      assert {200, ^before} = Api.request(port, "", "GET", "/health")
      assert {200, %{"jobs" => []}} = Api.request(port, "alice", "GET", "/jobs")
      assert {201, %{"id" => "j_1"}} = create(port)
      assert {200, %{"queued" => 1}} = Api.request(port, "", "GET", "/health")
    end
  end

  describe "the lease, the ack and the fail over the wire" do
    test "the whole life of a job", %{port: port, clock: clock} do
      assert {201, _job} =
               create(port, %{"queue" => "emails", "payload" => "hi", "max_tries" => 2})

      assert {200, leased} =
               Api.request(port, "bob", "POST", "/queues/emails/lease", ~s({"lease_ms":1000}))

      assert %{"state" => "leased", "tries" => 1, "worker" => "bob", "lease_until" => until} =
               leased

      assert {:ok, _datetime, 0} = DateTime.from_iso8601(until)

      assert {200, %{"state" => "queued", "reason" => "boom"}} =
               Api.request(port, "bob", "POST", "/jobs/j_1/fail", ~s({"reason":"boom"}))

      assert {200, %{"tries" => 2}} = Api.request(port, "eve", "POST", "/queues/emails/lease")
      assert {409, _error} = Api.request(port, "bob", "POST", "/jobs/j_1/ack")
      assert {200, %{"state" => "done"}} = Api.request(port, "eve", "POST", "/jobs/j_1/ack")

      Clock.advance(clock, 5_000)
      assert {200, %{"state" => "done"}} = Api.request(port, "eve", "GET", "/jobs/j_1")
    end

    test "a lease with no body takes the default, and a lease_ms out of range is 400", %{
      port: port
    } do
      assert {201, _job} = create(port)

      assert {200, %{"lease_until" => _until}} =
               Api.request(port, "bob", "POST", "/queues/emails/lease")

      assert {204, nil} = Api.request(port, "bob", "POST", "/queues/emails/lease")

      assert {400, _error} =
               Api.request(port, "bob", "POST", "/queues/emails/lease", ~s({"lease_ms":99}))

      assert {400, _error} =
               Api.request(port, "bob", "POST", "/queues/emails/lease", ~s({"lease_ms":3600001}))

      assert {400, _error} =
               Api.request(port, "bob", "POST", "/queues/emails/lease", ~s({"lease_ms":"long"}))

      assert {400, _error} =
               Api.request(port, "bob", "POST", "/queues/emails/lease", ~s({"ms":1000}))

      assert {400, _error} = Api.request(port, "bob", "POST", "/queues/a%20b/lease")
    end

    test "a fail with no reason keeps the job's, and a reason of the wrong shape is 400", %{
      port: port
    } do
      assert {201, _job} = create(port)
      assert {200, _job} = Api.request(port, "bob", "POST", "/queues/emails/lease")
      assert {200, job} = Api.request(port, "bob", "POST", "/jobs/j_1/fail")
      refute Map.has_key?(job, "reason")
      assert {400, _error} = Api.request(port, "bob", "POST", "/jobs/j_1/fail", ~s({"reason":7}))
      assert {400, _error} = Api.request(port, "bob", "POST", "/jobs/j_1/ack", ~s({"reason":"x"}))
    end

    test "an ack or a fail of a job that is not there is 404", %{port: port} do
      assert {404, _error} = Api.request(port, "bob", "POST", "/jobs/j_9/ack")
      assert {404, _error} = Api.request(port, "bob", "POST", "/jobs/j_9/fail")
      assert {404, _error} = Api.request(port, "bob", "GET", "/jobs/j_9")
      assert {404, _error} = Api.request(port, "bob", "DELETE", "/jobs/j_9")
    end
  end

  describe "the connection" do
    test "a malformed request line is 400", %{port: port} do
      assert String.starts_with?(Api.raw(port, "nonsense\r\n\r\n"), "HTTP/1.1 400")
    end

    test "a body without a content-length is not read", %{port: port} do
      response =
        Api.raw(
          port,
          "POST /jobs HTTP/1.1\r\nauthorization: Bearer alice\r\ntransfer-encoding: chunked\r\n\r\n0\r\n\r\n"
        )

      assert String.starts_with?(response, "HTTP/1.1 400")
    end

    test "keep-alive serves a second request on the same socket", %{port: port} do
      {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)
      request = "GET /health HTTP/1.1\r\nhost: x\r\nconnection: keep-alive\r\n\r\n"
      :ok = :gen_tcp.send(socket, [request, request])
      {:ok, bytes} = :gen_tcp.recv(socket, 0, 5_000)
      bytes = collect(socket, bytes)
      :gen_tcp.close(socket)

      assert length(String.split(bytes, "HTTP/1.1 200 OK")) == 3
    end
  end

  defp collect(socket, acc) do
    if length(String.split(acc, "HTTP/1.1 200 OK")) == 3 do
      acc
    else
      case :gen_tcp.recv(socket, 0, 2_000) do
        {:ok, bytes} -> collect(socket, acc <> bytes)
        {:error, _reason} -> acc
      end
    end
  end

  defp create(port, body \\ %{"queue" => "emails", "payload" => "hi", "max_tries" => 3}) do
    Api.request(port, "alice", "POST", "/jobs", JSON.encode!(body))
  end

  defp raw_without_token(port, method, path) do
    response = Api.raw(port, "#{method} #{path} HTTP/1.1\r\nhost: x\r\nconnection: close\r\n\r\n")
    [head | _rest] = String.split(response, "\r\n")
    [_version, status | _phrase] = String.split(head, " ")
    {String.to_integer(status), %{"error" => "unread"}}
  end
end
