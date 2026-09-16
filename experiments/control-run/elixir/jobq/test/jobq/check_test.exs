defmodule Jobq.CheckTest do
  use ExUnit.Case, async: true

  alias Jobq.Test.Service

  @timestamp ~r/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z/
  @uptime ~r/"uptime_ms":\d+/

  test "the check script plays through a real socket and says what the transcript says" do
    dir = Service.tmp_dir()
    {:ok, device} = StringIO.open("")

    assert :ok = Jobq.Check.run(dir, "script/check.script", device: device, sweep_ms: 50)

    {:ok, {_input, transcript}} = StringIO.close(device)
    assert normalize(transcript) == File.read!("script/expected.txt")
  end

  test "the same script twice on the same directory does not repeat an id" do
    dir = Service.tmp_dir()
    {:ok, device} = StringIO.open("")

    assert :ok = Jobq.Check.run(dir, "script/check.script", device: device)
    assert :ok = Jobq.Check.run(dir, "script/check.script", device: device)

    {:ok, {_input, transcript}} = StringIO.close(device)

    ids =
      Regex.scan(~r/"id":"(j_\d+)"/, transcript)
      |> Enum.map(fn [_match, id] -> id end)
      |> Enum.uniq()

    assert "j_4" in ids
    assert "j_6" in ids
  end

  test "a script that is not there is an error, and so is a line that is not a request" do
    dir = Service.tmp_dir()
    assert {:error, {:script, _path, :enoent}} = Jobq.Check.run(dir, Path.join(dir, "nope"))

    script = Path.join(dir, "bad.script")
    File.write!(script, "alice GET\n")
    {:ok, device} = StringIO.open("")
    assert {:error, {:script_line, "alice GET"}} = Jobq.Check.run(dir, script, device: device)
  end

  defp normalize(text) do
    text
    |> then(&Regex.replace(@timestamp, &1, "<ts>"))
    |> then(&Regex.replace(@uptime, &1, ~s("uptime_ms":<ms>)))
  end
end
