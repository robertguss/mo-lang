defmodule Jobq.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO, only: [with_io: 1, with_io: 2]

  alias Jobq.CLI
  alias Jobq.Test.Service

  test "a command that is not one of the four is a usage error" do
    assert {2, output} = run([])
    assert output =~ "usage: jobq serve"
    assert {2, _output} = run(["dance"])
    assert {2, _output} = run(["serve"])
    assert {2, _output} = run(["compact"])
    assert {2, _output} = run(["check", "one"])
    assert {2, _output} = run(["client", "127.0.0.1", "7900", "alice", "GET"])
  end

  test "an option or a port that is not a number is a usage error" do
    dir = Service.tmp_dir()
    assert {2, _output} = run(["serve", dir, "--port", "seven"])
    assert {2, _output} = run(["serve", dir, "--port", "99999"])
    assert {2, _output} = run(["serve", dir, "--quiet"])
    assert {2, _output} = run(["client", "127.0.0.1", "seven", "alice", "GET", "/health"])
  end

  test "a directory that cannot be opened is 1" do
    assert {1, output} = run(["compact", "/proc/self/mem/nope"])
    assert output =~ "cannot open"
    assert {1, _output} = run(["serve", "/proc/self/mem/nope"])
    assert {1, _output} = run(["check", "/proc/self/mem/nope", "script/check.script"])
  end

  test "a port that cannot be bound is 1" do
    dir = Service.tmp_dir()
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)

    assert {1, output} = run(["serve", dir, "--port", Integer.to_string(port)])
    assert output =~ "cannot bind port #{port}"

    :gen_tcp.close(socket)
  end

  test "a client that cannot reach the service is 1" do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)

    assert {1, output} =
             run(["client", "127.0.0.1", Integer.to_string(port), "a", "GET", "/health"])

    assert output =~ "econnrefused"
  end

  test "compact says how many jobs it kept, and check plays a script" do
    dir = Service.tmp_dir()
    assert {0, output} = run(["compact", dir])
    assert output =~ "compacted"
    assert output =~ "0 job(s)"

    assert {0, output} = run(["check", dir, "script/check.script"])
    assert output =~ ~s(< 201 {"id":"j_1")

    assert {0, output} = run(["compact", dir])
    assert output =~ "2 job(s)"
  end

  test "the client prints the status and the body of a request it made" do
    %{port: port} = Service.start()

    assert {0, output} =
             run([
               "client",
               "127.0.0.1",
               Integer.to_string(port),
               "alice",
               "POST",
               "/jobs",
               ~s({"queue":"emails","payload":"hi","max_attempts":1})
             ])

    assert output =~ ~s(201 {"id":"j_1")

    assert {0, output} =
             run([
               "client",
               "127.0.0.1",
               Integer.to_string(port),
               "bob",
               "POST",
               "/queues/other/lease"
             ])

    assert String.trim(output) == "204"
  end

  defp run(argv) do
    {{status, stdout}, stderr} =
      with_io(:stderr, fn -> with_io(fn -> CLI.run(argv) end) end)

    {status, stdout <> stderr}
  end
end
