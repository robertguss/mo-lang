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
    check all(payload <- payload(), max_runs: 500) do
      job = %Job{
        n: 1,
        queue: "emails",
        payload: payload,
        max_attempts: 3,
        attempts: 0,
        state: :queued,
        created_at: 1_789_000_000_000,
        updated_at: 1_789_000_000_000
      }

      assert {:ok, ^payload} = Job.payload(payload)

      assert {:ok, ^job} =
               job |> Job.record() |> Jobq.Json.encode() |> JSON.decode!() |> Job.from_record()
    end
  end

  property "create then get gives the payload back, over the wire" do
    %{port: port} = Service.start()

    check all(
            payload <- payload(),
            queue <- queue_name(),
            max_attempts <- StreamData.integer(1..100),
            max_runs: 100
          ) do
      body =
        JSON.encode!(%{"queue" => queue, "payload" => payload, "max_attempts" => max_attempts})

      assert {201, created} = Api.request(port, "alice", "POST", "/jobs", body)
      assert created["payload"] == payload
      assert created["queue"] == queue
      assert created["max_attempts"] == max_attempts

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
      body = JSON.encode!(%{"queue" => "emails", "payload" => payload, "max_attempts" => 1})
      assert {400, %{"error" => _why}} = Api.request(port, "alice", "POST", "/jobs", body)
    end
  end
end
