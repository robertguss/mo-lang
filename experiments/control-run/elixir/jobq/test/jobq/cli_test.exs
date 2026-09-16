defmodule Jobq.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO, only: [with_io: 1, with_io: 2]

  alias Jobq.CLI
  alias Jobq.Store
  alias Jobq.Test.Service

  test "a command that is not one of the four is a usage error" do
    assert {2, output} = run([])
    assert output =~ "usage: jobq serve"
    assert {2, _output} = run(["dance"])
    assert {2, _output} = run(["serve"])
    assert {2, _output} = run(["compact"])
    assert {2, _output} = run(["check", "one"])
    assert {2, _output} = run(["verify"])
    assert {2, _output} = run(["verify", "one", "two"])
    assert {2, _output} = run(["client", "127.0.0.1", "7900", "alice", "GET"])
  end

  test "an option or a port that is not a number is a usage error" do
    dir = Service.tmp_dir()
    assert {2, _output} = run(["serve", dir, "--port", "seven"])
    assert {2, _output} = run(["serve", dir, "--port", "99999"])
    assert {2, _output} = run(["serve", dir, "--quiet"])
    assert {2, _output} = run(["serve", dir, "--max-restarts", "-1"])
    assert {2, _output} = run(["serve", dir, "--restart-window", "0"])
    assert {2, _output} = run(["serve", dir, "--crash-every", "often"])
    assert {2, _output} = run(["serve", dir, "--crash-every"])
    assert {2, _output} = run(["compact", dir, "--crash-every", "1"])
    assert {2, _output} = run(["verify", dir, "--crash-every", "1"])
    assert {2, _output} = run(["client", "127.0.0.1", "seven", "alice", "GET", "/health"])
  end

  test "a directory that cannot be opened is 1" do
    assert {1, output} = run(["compact", "/proc/self/mem/nope"])
    assert output =~ "cannot open"
    assert {1, _output} = run(["serve", "/proc/self/mem/nope"])
    assert {1, _output} = run(["check", "/proc/self/mem/nope", "script/check.script"])
    assert {1, _output} = run(["verify", "/proc/self/mem/nope"])
  end

  describe "verify" do
    test "a folder that opens is 0, with its counts and the next id" do
      dir = Service.tmp_dir()
      assert {0, output} = run(["verify", dir])

      assert output =~
               "0 jobs: queued 0, scheduled 0, leased 0, done 0, dead 0; next id j_1; archived 0"

      # The program's own fixture folders, the one the round 7 escript wrote
      # and the one this version writes.
      assert {0, output} = run(["verify", "test/fixtures/round7/data"])

      assert output =~
               "5 jobs: queued 1, scheduled 0, leased 2, done 1, dead 1; next id j_7; archived 0"

      assert {0, _output} = run(["check", dir, "script/check.script"])
      assert {0, output} = run(["verify", dir])
      # The script's two done jobs were archived, and one of them was deleted.
      assert output =~
               "4 jobs: queued 2, scheduled 1, leased 1, done 0, dead 0; next id j_9; archived 1"
    end

    test "a record that is not well-formed is 1, named with its key and its rule" do
      dir = ill_formed_dir()

      assert {1, output} = run(["verify", dir])
      assert output =~ "jobq: #{dir}: record j_2: a leased job has a worker and a lease_until"

      # And the same folder is refused by everything else that opens one.
      assert {1, output} = run(["serve", dir])
      assert output =~ "record j_2:"
      assert {1, output} = run(["compact", dir])
      assert output =~ "record j_2:"
      assert {1, _output} = run(["check", dir, "script/check.script"])

      # Nothing was rewritten: the folder is as it was.
      assert File.read!(Store.log_path(dir)) =~ ~s("id":"j_2")
    end

    test "a torn last line is still cut off rather than refused" do
      dir = Service.tmp_dir()
      File.write!(Store.log_path(dir), well_formed() <> ~s({"id":"j_2","queue":"ema))

      assert {0, output} = run(["verify", dir])
      assert output =~ "1 jobs: queued 1,"
    end
  end

  test "a port that cannot be bound is 1" do
    dir = Service.tmp_dir()
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)

    assert {1, output} = run(["serve", dir, "--port", Integer.to_string(port)])
    assert output =~ "cannot bind port #{port}"

    :gen_tcp.close(socket)
  end

  describe "serve's restart budget" do
    test "a board that fails past its budget is 70, and the folder verifies" do
      dir = Service.tmp_dir()

      serving =
        Task.async(fn ->
          run(~w(serve #{dir} --port 0 --crash-every 1 --max-restarts 2 --restart-window 60))
        end)

      port = wait_port()

      # Every write fails the board; the third failure is one past the budget.
      statuses =
        Enum.map(1..3, fn n ->
          body = ~s({"queue":"emails","payload":"#{n}","max_tries":1})
          answer = Jobq.Client.request({127, 0, 0, 1}, port, "alice", "POST", "/jobs", body)
          wait_board()
          answer
        end)

      assert Enum.all?(statuses, &match?({:ok, 503, _body}, &1))
      assert {70, output} = Task.await(serving, 10_000)
      assert output =~ "failed more than 2 time(s) inside 60 second(s)"

      assert {0, output} = run(["verify", dir])
      assert output =~ "3 jobs: queued 3,"
    end

    test "the options are taken in any order" do
      dir = Service.tmp_dir()

      serving =
        Task.async(fn ->
          run(~w(serve #{dir} --restart-window 30 --crash-every 0 --max-restarts 1 --port 0))
        end)

      port = wait_port()
      board = Jobq.Registry.whereis(:default, :board)
      Process.exit(Jobq.Registry.whereis(:default, :queue), :kill)
      wait_board()

      assert {:ok, 200, body} = Jobq.Client.request({127, 0, 0, 1}, port, "", "GET", "/health")
      assert %{"restarts" => 1} = JSON.decode!(body)
      assert Jobq.Registry.whereis(:default, :board) == board

      Process.exit(Jobq.Registry.whereis(:default, :store), :kill)
      assert {70, _output} = Task.await(serving, 10_000)
    end
  end

  # The port of the service `serve` started, once it is listening.
  defp wait_port(tries \\ 500) do
    case Jobq.Registry.whereis(:default, :socket) do
      nil when tries > 0 ->
        Process.sleep(10)
        wait_port(tries - 1)

      _pid ->
        Jobq.Server.port(:default)
    end
  end

  # The board back after a failure, or gone for good.
  defp wait_board(tries \\ 500) do
    board = Jobq.Registry.whereis(:default, :board)
    queue = Jobq.Registry.whereis(:default, :queue)

    cond do
      is_nil(board) or not Process.alive?(board) ->
        :gone

      is_pid(queue) and Process.alive?(queue) ->
        :ok

      tries == 0 ->
        :timeout

      true ->
        Process.sleep(10)
        wait_board(tries - 1)
    end
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

    # The script leaves j_2 leased, j_4 scheduled, and j_7 and j_8 queued; j_3
    # and j_5 it deletes, j_1 it archives, and j_6 it archives and deletes. The
    # compaction keeps j_1 in the archive and nothing of j_6 anywhere.
    assert {0, output} = run(["compact", dir])
    assert output =~ "4 job(s)"
    refute File.read!(Store.log_path(dir)) =~ ~s("id":"j_1")
    assert File.read!(Store.archive_path(dir)) =~ ~s("id":"j_1")
    refute File.read!(Store.archive_path(dir)) =~ ~s("id":"j_6")
    assert {0, output} = run(["verify", dir])
    assert output =~ "4 jobs:"
    assert output =~ "; next id j_9; archived 1"
  end

  describe "the archive" do
    test "--retain-ms is 1,000 to 2,678,400,000" do
      dir = Service.tmp_dir()
      assert {2, output} = run(["serve", dir, "--retain-ms", "999"])
      assert output =~ "--retain-ms must be a number from 1000 to 2678400000"
      assert {2, _output} = run(["serve", dir, "--retain-ms", "2678400001"])
      assert {2, _output} = run(["serve", dir, "--retain-ms", "a day"])
      assert {2, output} = run([])
      assert output =~ "[--retain-ms N]"
    end

    test "a bad archive record refuses the folder in verify, serve, and compact" do
      dir = Service.tmp_dir()
      File.write!(Store.log_path(dir), well_formed())

      File.write!(Store.archive_path(dir), """
      {"id":"j_2","queue":"emails","state":"queued","payload":"hi","tries":0,"max_tries":3,"backoff_ms":0,"created_at":1789000000000,"updated_at":1789000000000,"archived_at":1789000000000}
      """)

      assert {1, output} = run(["verify", dir])
      assert output =~ "jobq: #{dir}: record j_2: an archived job is done or dead"
      assert {1, output} = run(["serve", dir])
      assert output =~ "record j_2:"
      assert {1, output} = run(["compact", dir])
      assert output =~ "record j_2:"
      assert File.read!(Store.archive_path(dir)) =~ ~s("id":"j_2")

      File.write!(Store.archive_path(dir), "not json\n")
      assert {1, output} = run(["verify", dir])
      assert output =~ "the archive is corrupt at line 1"
    end
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
               ~s({"queue":"emails","payload":"hi","max_tries":1})
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

  defp ill_formed_dir do
    dir = Service.tmp_dir()

    File.write!(
      Store.log_path(dir),
      well_formed() <>
        ~s({"id":"j_2","queue":"emails","state":"leased","payload":"held","tries":1,) <>
        ~s("max_tries":3,"backoff_ms":0,"created_at":1789000000000,) <>
        ~s("updated_at":1789000000000}\n)
    )

    dir
  end

  defp well_formed do
    ~s({"id":"j_1","queue":"emails","state":"queued","payload":"hi","tries":0,) <>
      ~s("max_tries":3,"backoff_ms":0,"created_at":1789000000000,) <>
      ~s("updated_at":1789000000000}\n)
  end

  defp run(argv) do
    {{status, stdout}, stderr} =
      with_io(:stderr, fn -> with_io(fn -> CLI.run(argv) end) end)

    {status, stdout <> stderr}
  end
end
