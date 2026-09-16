defmodule Jobq.ListenerTest do
  use ExUnit.Case, async: false

  alias Jobq.Test.Api
  alias Jobq.Test.Service

  @tag timeout: 120_000
  test "1,200 connections that say nothing do not keep a producer waiting" do
    %{port: port} = Service.start(idle_ms: 60_000, acceptors: 10)

    silent =
      for _n <- 1..1_200 do
        {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)
        socket
      end

    assert length(silent) == 1_200

    {microseconds, answer} =
      :timer.tc(fn ->
        Api.request(
          port,
          "alice",
          "POST",
          "/jobs",
          ~s({"queue":"emails","payload":"hi","max_attempts":1})
        )
      end)

    assert {201, %{"id" => "j_1"}} = answer
    assert microseconds < 1_000_000

    # And the same once they are gone.
    Enum.each(silent, &:gen_tcp.close/1)
    assert {200, %{"queued" => 1}} = Api.request(port, "alice", "GET", "/health")
  end

  test "a connection that says nothing is closed when its idle time is up" do
    %{port: port} = Service.start(idle_ms: 200)
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)

    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 5_000)
  end

  test "a request that stops halfway is closed when its time is up, and the service is fine" do
    %{port: port} = Service.start(idle_ms: 5_000, request_ms: 200)
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)
    :ok = :gen_tcp.send(socket, "POST /jobs HTTP/1.1\r\nauthorization: Bearer alice\r\n")

    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 5_000)
    assert {200, %{"queued" => 0}} = Api.request(port, "alice", "GET", "/health")
  end

  test "a body that never arrives does not hold the queue" do
    %{port: port} = Service.start(idle_ms: 5_000, request_ms: 300)
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)

    :ok =
      :gen_tcp.send(
        socket,
        "POST /jobs HTTP/1.1\r\nauthorization: Bearer alice\r\ncontent-length: 50\r\n\r\n{"
      )

    assert {201, _job} =
             Api.request(
               port,
               "alice",
               "POST",
               "/jobs",
               ~s({"queue":"emails","payload":"hi","max_attempts":1})
             )

    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 5_000)
  end
end
