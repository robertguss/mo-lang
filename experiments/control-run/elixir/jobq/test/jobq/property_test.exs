defmodule Jobq.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Jobq.Job
  alias Jobq.Test.Api
  alias Jobq.Test.Service

  # Every payload the spec allows: UTF-8 with no control character but a
  # newline, up to 60 KiB. The generator stays well inside the length so a
  # property run is about the bytes, not the limit, which has its own test.
  defp payload do
    StreamData.string([?\n, 0x20..0x7E, 0xA0..0x24F, 0x370..0x3FF, 0x4E00..0x4E80],
      max_length: 300
    )
  end

  defp queue_name do
    StreamData.string([?a..?z, ?A..?Z, ?0..?9, ?-, ?_], min_length: 1, max_length: 64)
  end

  property "a record round-trips a payload through the store's shape" do
    check all(payload <- payload(), backoff_ms <- StreamData.integer(0..3_600_000), max_runs: 500) do
      job = %Job{
        n: 1,
        queue: "emails",
        payload: payload,
        max_tries: 3,
        tries: 0,
        backoff_ms: backoff_ms,
        state: :queued,
        created_at: 1_789_000_000_000,
        updated_at: 1_789_000_000_000
      }

      assert {:ok, ^payload} = Job.payload(payload)

      assert {:ok, ^job} =
               job |> Job.record() |> Jobq.Json.encode() |> JSON.decode!() |> Job.from_record()

      scheduled = %{job | state: :scheduled, run_at: 1_789_000_060_000}

      assert {:ok, ^scheduled} =
               scheduled
               |> Job.record()
               |> Jobq.Json.encode()
               |> JSON.decode!()
               |> Job.from_record()
    end
  end

  property "create then get gives the payload back, over the wire" do
    %{port: port} = Service.start()

    check all(
            payload <- payload(),
            queue <- queue_name(),
            max_tries <- StreamData.integer(1..100),
            delay_ms <- StreamData.integer(0..86_400_000),
            backoff_ms <- StreamData.integer(0..3_600_000),
            max_runs: 100
          ) do
      body =
        JSON.encode!(%{
          "queue" => queue,
          "payload" => payload,
          "max_tries" => max_tries,
          "delay_ms" => delay_ms,
          "backoff_ms" => backoff_ms
        })

      assert {201, created} = Api.request(port, "alice", "POST", "/jobs", body)
      assert created["payload"] == payload
      assert created["queue"] == queue
      assert created["max_tries"] == max_tries
      assert created["backoff_ms"] == backoff_ms
      assert created["state"] == if(delay_ms > 0, do: "scheduled", else: "queued")
      refute Map.has_key?(created, "delay_ms")

      assert {200, read} = Api.request(port, "alice", "GET", "/jobs/" <> created["id"])
      assert read == created
    end
  end

  property "a payload the rules refuse never reaches a job" do
    %{port: port} = Service.start()

    check all(
            payload <-
              StreamData.one_of([
                StreamData.string([0x00..0x08, 0x0B..0x1F, 0x7F], min_length: 1, max_length: 8),
                StreamData.integer(),
                StreamData.boolean()
              ]),
            max_runs: 100
          ) do
      body = JSON.encode!(%{"queue" => "emails", "payload" => payload, "max_tries" => 1})
      assert {400, %{"error" => _why}} = Api.request(port, "alice", "POST", "/jobs", body)
    end
  end

  property "a delay or a backoff the rules refuse never reaches a job" do
    %{port: port} = Service.start()

    check all(
            field <- StreamData.member_of(["delay_ms", "backoff_ms"]),
            value <-
              StreamData.one_of([
                StreamData.integer(-1_000_000..-1),
                StreamData.integer(86_400_001..90_000_000),
                StreamData.string(:alphanumeric),
                StreamData.boolean()
              ]),
            max_runs: 100
          ) do
      body =
        JSON.encode!(
          Map.put(%{"queue" => "emails", "payload" => "hi", "max_tries" => 1}, field, value)
        )

      assert {400, %{"error" => _why}} = Api.request(port, "alice", "POST", "/jobs", body)
    end
  end
end
