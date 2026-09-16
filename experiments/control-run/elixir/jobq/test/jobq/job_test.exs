defmodule Jobq.JobTest do
  use ExUnit.Case, async: true

  alias Jobq.Job

  describe "the queue name" do
    test "takes 1 to 64 bytes of letters, digits, '-' and '_'" do
      assert {:ok, "emails"} = Job.queue("emails")
      assert {:ok, "a-b_C9"} = Job.queue("a-b_C9")
      assert {:ok, _name} = Job.queue(String.duplicate("q", 64))
    end

    test "rejects what is empty, too long, or not a name" do
      assert {:error, _why} = Job.queue("")
      assert {:error, _why} = Job.queue(String.duplicate("q", 65))
      assert {:error, _why} = Job.queue("has space")
      assert {:error, _why} = Job.queue("dots.are.out")
      assert {:error, _why} = Job.queue(7)
    end
  end

  describe "the payload" do
    test "takes 0 to 60 KiB of UTF-8, and a newline" do
      assert {:ok, ""} = Job.payload("")
      assert {:ok, "a\nb"} = Job.payload("a\nb")
      assert {:ok, _text} = Job.payload(String.duplicate("x", 61_440))
    end

    test "rejects a control character, bad UTF-8, too many bytes, or a non-string" do
      assert {:error, _why} = Job.payload("a\tb")
      assert {:error, _why} = Job.payload("a" <> <<0>>)
      assert {:error, _why} = Job.payload("a" <> <<0x7F>>)
      assert {:error, _why} = Job.payload(<<0xFF, 0xFE>>)
      assert {:error, _why} = Job.payload(String.duplicate("x", 61_441))
      assert {:error, _why} = Job.payload(nil)
    end
  end

  describe "max_tries, lease_ms, delay_ms and backoff_ms" do
    test "take their range and nothing else" do
      assert {:ok, 1} = Job.max_tries(1)
      assert {:ok, 100} = Job.max_tries(100)
      assert {:error, _why} = Job.max_tries(0)
      assert {:error, _why} = Job.max_tries(101)
      assert {:error, _why} = Job.max_tries("3")
      assert {:error, _why} = Job.max_tries(3.0)

      assert {:ok, 100} = Job.lease_ms(100)
      assert {:ok, 3_600_000} = Job.lease_ms(3_600_000)
      assert {:error, _why} = Job.lease_ms(99)
      assert {:error, _why} = Job.lease_ms(3_600_001)
      assert {:error, _why} = Job.lease_ms(nil)

      assert {:ok, 0} = Job.delay_ms(0)
      assert {:ok, 86_400_000} = Job.delay_ms(86_400_000)
      assert {:error, _why} = Job.delay_ms(-1)
      assert {:error, _why} = Job.delay_ms(86_400_001)
      assert {:error, _why} = Job.delay_ms("soon")

      assert {:ok, 0} = Job.backoff_ms(0)
      assert {:ok, 3_600_000} = Job.backoff_ms(3_600_000)
      assert {:error, _why} = Job.backoff_ms(-1)
      assert {:error, _why} = Job.backoff_ms(3_600_001)
      assert {:error, _why} = Job.backoff_ms(1.5)
    end
  end

  describe "ids" do
    test "render and parse" do
      job = job(7)
      assert Job.id(job) == "j_7"
      assert {:ok, 7} = Job.parse_id("j_7")
      assert :error = Job.parse_id("j_0")
      assert :error = Job.parse_id("j_")
      assert :error = Job.parse_id("7")
      assert :error = Job.parse_id("j_7x")
    end
  end

  describe "the two shapes" do
    test "a queued job renders without a worker or a reason" do
      assert {:obj, fields} = Job.render(job(1))

      assert Keyword.keys(rename(fields)) ==
               ~w(id queue state payload tries max_tries backoff_ms created_at updated_at)a
    end

    test "a scheduled job renders its run_at, and nothing else does" do
      scheduled = %{job(1) | state: :scheduled, run_at: 1_789_000_060_000}
      {:obj, fields} = Job.render(scheduled)
      assert {"state", "scheduled"} in fields
      assert {"run_at", "2026-09-10T00:27:40.000Z"} in fields

      {:obj, queued} = Job.render(%{job(1) | run_at: 1_789_000_060_000})
      refute Enum.any?(queued, fn {key, _value} -> key == "run_at" end)
    end

    test "a leased job renders its worker and lease, a failed job its reason" do
      leased = %{job(1) | state: :leased, worker: "bob", lease_until: 1_789_000_060_000}
      {:obj, fields} = Job.render(leased)
      assert {"worker", "bob"} in fields
      assert {"lease_until", "2026-09-10T00:27:40.000Z"} in fields

      {:obj, failed} = Job.render(%{job(1) | state: :queued, reason: "boom"})
      assert {"reason", "boom"} in failed
    end

    test "a record round-trips through the store's shape" do
      job = %{job(3) | state: :leased, worker: "bob", lease_until: 1_789_000_060_000, tries: 2}
      record = job |> Job.record() |> Jobq.Json.encode() |> JSON.decode!()
      assert {:ok, ^job} = Job.from_record(record)
    end

    test "a record that is missing a field, or has one of the wrong shape, is not a job" do
      record = job(1) |> Job.record() |> Jobq.Json.encode() |> JSON.decode!()
      assert :error = Job.from_record(Map.delete(record, "queue"))
      assert :error = Job.from_record(Map.put(record, "tries", "two"))
      assert :error = Job.from_record(Map.put(record, "state", "sideways"))
      assert :error = Job.from_record(Map.put(record, "id", "nope"))
      assert :error = Job.from_record("not a record")
    end

    test "a scheduled record without a run_at is not a job" do
      record =
        %{job(1) | state: :scheduled, run_at: 1_789_000_060_000}
        |> Job.record()
        |> Jobq.Json.encode()
        |> JSON.decode!()

      assert {:ok, %Job{state: :scheduled, run_at: 1_789_000_060_000}} = Job.from_record(record)
      assert :error = Job.from_record(Map.delete(record, "run_at"))
      assert :error = Job.from_record(Map.put(record, "run_at", "soon"))
    end
  end

  describe "a record the version before the change wrote" do
    test "reads attempts as tries, max_attempts as max_tries, and no backoff as 0" do
      old = %{
        "id" => "j_4",
        "queue" => "emails",
        "state" => "leased",
        "payload" => "hi",
        "attempts" => 2,
        "max_attempts" => 3,
        "created_at" => 1_789_000_000_000,
        "updated_at" => 1_789_000_030_000,
        "worker" => "bob",
        "lease_until" => 1_789_000_060_000
      }

      assert {:ok, job} = Job.from_record(old)

      assert %Job{
               n: 4,
               state: :leased,
               tries: 2,
               max_tries: 3,
               backoff_ms: 0,
               run_at: nil,
               worker: "bob",
               lease_until: 1_789_000_060_000
             } = job
    end

    test "is written back under the new names only" do
      old = %{
        "id" => "j_1",
        "queue" => "emails",
        "state" => "queued",
        "payload" => "hi",
        "attempts" => 0,
        "max_attempts" => 1,
        "created_at" => 1_789_000_000_000,
        "updated_at" => 1_789_000_000_000
      }

      assert {:ok, job} = Job.from_record(old)
      line = job |> Job.record() |> Jobq.Json.encode()
      refute line =~ "attempts"
      assert line =~ ~s("tries":0)
      assert line =~ ~s("max_tries":1)
      assert line =~ ~s("backoff_ms":0)
    end

    test "still needs a count of tries under one name or the other" do
      old = %{
        "id" => "j_1",
        "queue" => "emails",
        "state" => "queued",
        "payload" => "hi",
        "max_attempts" => 1,
        "created_at" => 1_789_000_000_000,
        "updated_at" => 1_789_000_000_000
      }

      assert :error = Job.from_record(old)
      assert :error = Job.from_record(Map.delete(Map.put(old, "attempts", 0), "max_attempts"))
    end
  end

  describe "check_record/1: the rule a record on the disk must meet" do
    test "a well-formed record of every state" do
      assert :ok = Job.check_record(queued())
      assert :ok = Job.check_record(scheduled())
      assert :ok = Job.check_record(leased())
      assert :ok = Job.check_record(finished("done"))
      assert :ok = Job.check_record(finished("dead"))
    end

    test "a queued job has a try left and carries nothing of a lease or a delay" do
      assert {:error, "a queued job has tried fewer times than its max_tries"} =
               Job.check_record(%{queued() | "tries" => 3})

      assert {:error, "a queued job has no run_at"} =
               Job.check_record(Map.put(queued(), "run_at", 1_789_000_060_000))

      assert {:error, "a queued job has no worker"} =
               Job.check_record(Map.put(queued(), "worker", "bob"))

      assert {:error, "a queued job has no lease_until"} =
               Job.check_record(Map.put(queued(), "lease_until", 1_789_000_060_000))
    end

    test "a scheduled job has a run_at and no lease" do
      assert {:error, "a scheduled job has a run_at"} =
               Job.check_record(Map.delete(scheduled(), "run_at"))

      assert {:error, "a scheduled job's run_at is an instant in milliseconds"} =
               Job.check_record(%{scheduled() | "run_at" => "tomorrow"})

      assert {:error, "a scheduled job has no worker"} =
               Job.check_record(Map.put(scheduled(), "worker", "bob"))

      assert {:error, "a scheduled job has tried fewer times than its max_tries"} =
               Job.check_record(%{scheduled() | "tries" => 3})
    end

    test "a leased job has a worker and a lease_until, and has been tried" do
      assert {:error, "a leased job has a worker and a lease_until"} =
               Job.check_record(Map.delete(leased(), "worker"))

      assert {:error, "a leased job has a worker and a lease_until"} =
               Job.check_record(%{leased() | "lease_until" => nil})

      assert {:error, "a leased job has no run_at"} =
               Job.check_record(Map.put(leased(), "run_at", 1_789_000_060_000))

      assert {:error, "a leased job has tried at least once and at most its max_tries"} =
               Job.check_record(%{leased() | "tries" => 0})

      assert {:error, "a leased job has tried at least once and at most its max_tries"} =
               Job.check_record(%{leased() | "tries" => 4})
    end

    test "a done or dead job has been tried and holds nothing else" do
      for state <- ["done", "dead"] do
        record = finished(state)

        assert Job.check_record(%{record | "tries" => 0}) ==
                 {:error, "a #{state} job has tried at least once and at most its max_tries"}

        assert Job.check_record(Map.put(record, "worker", "bob")) ==
                 {:error, "a #{state} job has no worker"}

        assert Job.check_record(Map.put(record, "run_at", 1_789_000_060_000)) ==
                 {:error, "a #{state} job has no run_at"}
      end

      # The reason a job was failed with belongs to no state in particular.
      assert :ok = Job.check_record(Map.put(finished("dead"), "reason", "smtp said no"))
      assert :ok = Job.check_record(Map.put(queued(), "reason", "smtp said no"))
    end

    test "the key names the job's id" do
      assert {:error, "the key must name the job's id, 'j_' and a counter"} =
               Job.check_record(Map.delete(queued(), "id"))

      assert {:error, "the key must name the job's id, 'j_' and a counter"} =
               Job.check_record(%{queued() | "id" => "seven"})

      assert Job.record_key(queued()) == "j_1"
      assert Job.record_key(%{}) == "?"
    end

    test "the fields keep the rules the API holds them to" do
      assert {:error, "queue must be letters, digits, '-' or '_'"} =
               Job.check_record(%{queued() | "queue" => "em ails"})

      assert {:error, "payload must be a string"} =
               Job.check_record(%{queued() | "payload" => 7})

      assert {:error, "max_tries must be 1 to 100"} =
               Job.check_record(%{queued() | "max_tries" => 0})

      assert {:error, "backoff_ms must be 0 to 3600000"} =
               Job.check_record(%{queued() | "backoff_ms" => 3_600_001})

      assert {:error, "tries must be an integer"} =
               Job.check_record(%{queued() | "tries" => "one"})

      assert {:error, "created_at must be an instant in milliseconds"} =
               Job.check_record(%{queued() | "created_at" => "yesterday"})

      assert {:error, "state must be queued, scheduled, leased, done or dead"} =
               Job.check_record(%{queued() | "state" => "sideways"})

      assert {:error, "'state' is required"} = Job.check_record(Map.delete(queued(), "state"))
      assert {:error, "'tries' is required"} = Job.check_record(Map.delete(queued(), "tries"))
      assert {:error, "a record must be a JSON object"} = Job.check_record("j_1")
    end

    test "the shape the version before change 1 wrote is well-formed too" do
      old =
        queued()
        |> Map.drop(["tries", "max_tries", "backoff_ms"])
        |> Map.merge(%{"attempts" => 0, "max_attempts" => 3})

      assert :ok = Job.check_record(old)

      assert {:error, "'max_tries' is required"} =
               Job.check_record(Map.delete(old, "max_attempts"))
    end

    test "every record the store writes is well-formed" do
      for state <- [:queued, :scheduled, :leased, :done, :dead] do
        record =
          1
          |> job()
          |> Map.merge(shape(state))
          |> Job.record()
          |> encode_decode()

        assert :ok = Job.check_record(record)
      end
    end
  end

  defp shape(:queued), do: %{state: :queued}
  defp shape(:scheduled), do: %{state: :scheduled, run_at: 1_789_000_060_000}

  defp shape(:leased),
    do: %{state: :leased, tries: 1, worker: "bob", lease_until: 1_789_000_060_000}

  defp shape(state), do: %{state: state, tries: 1}

  defp encode_decode(record) do
    {:ok, map} = record |> Jobq.Json.encode() |> Jobq.Json.decode()
    map
  end

  defp queued do
    %{
      "id" => "j_1",
      "queue" => "emails",
      "state" => "queued",
      "payload" => "hi",
      "tries" => 0,
      "max_tries" => 3,
      "backoff_ms" => 0,
      "created_at" => 1_789_000_000_000,
      "updated_at" => 1_789_000_000_000
    }
  end

  defp scheduled, do: %{queued() | "state" => "scheduled"} |> Map.put("run_at", 1_789_000_060_000)

  defp leased do
    queued()
    |> Map.merge(%{"state" => "leased", "tries" => 1})
    |> Map.merge(%{"worker" => "bob", "lease_until" => 1_789_000_060_000})
  end

  defp finished(state), do: %{queued() | "state" => state, "tries" => 1}

  defp job(n) do
    %Job{
      n: n,
      queue: "emails",
      payload: "hi",
      max_tries: 3,
      tries: 0,
      state: :queued,
      created_at: 1_789_000_000_000,
      updated_at: 1_789_000_000_000
    }
  end

  defp rename(fields), do: Enum.map(fields, fn {key, value} -> {String.to_atom(key), value} end)
end
