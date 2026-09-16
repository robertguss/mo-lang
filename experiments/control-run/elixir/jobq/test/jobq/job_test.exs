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

  describe "max_attempts and lease_ms" do
    test "take their range and nothing else" do
      assert {:ok, 1} = Job.max_attempts(1)
      assert {:ok, 100} = Job.max_attempts(100)
      assert {:error, _why} = Job.max_attempts(0)
      assert {:error, _why} = Job.max_attempts(101)
      assert {:error, _why} = Job.max_attempts("3")
      assert {:error, _why} = Job.max_attempts(3.0)

      assert {:ok, 100} = Job.lease_ms(100)
      assert {:ok, 3_600_000} = Job.lease_ms(3_600_000)
      assert {:error, _why} = Job.lease_ms(99)
      assert {:error, _why} = Job.lease_ms(3_600_001)
      assert {:error, _why} = Job.lease_ms(nil)
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
      assert Keyword.keys(rename(fields)) == ~w(id queue state payload attempts max_attempts created_at updated_at)a
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
      job = %{job(3) | state: :leased, worker: "bob", lease_until: 1_789_000_060_000, attempts: 2}
      record = job |> Job.record() |> Jobq.Json.encode() |> JSON.decode!()
      assert {:ok, ^job} = Job.from_record(record)
    end

    test "a record that is missing a field, or has one of the wrong shape, is not a job" do
      record = job(1) |> Job.record() |> Jobq.Json.encode() |> JSON.decode!()
      assert :error = Job.from_record(Map.delete(record, "queue"))
      assert :error = Job.from_record(Map.put(record, "attempts", "two"))
      assert :error = Job.from_record(Map.put(record, "state", "sideways"))
      assert :error = Job.from_record(Map.put(record, "id", "nope"))
      assert :error = Job.from_record("not a record")
    end
  end

  defp job(n) do
    %Job{
      n: n,
      queue: "emails",
      payload: "hi",
      max_attempts: 3,
      attempts: 0,
      state: :queued,
      created_at: 1_789_000_000_000,
      updated_at: 1_789_000_000_000
    }
  end

  defp rename(fields), do: Enum.map(fields, fn {key, value} -> {String.to_atom(key), value} end)
end
