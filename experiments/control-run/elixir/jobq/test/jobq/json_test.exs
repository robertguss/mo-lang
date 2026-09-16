defmodule Jobq.JsonTest do
  use ExUnit.Case, async: true

  alias Jobq.Json

  doctest Jobq.Json

  test "an object keeps the order its keys are written in" do
    object = {:obj, [{"z", 1}, {"a", 2}, {"m", {:obj, [{"b", true}, {"a", nil}]}}]}
    assert Json.encode(object) == ~s({"z":1,"a":2,"m":{"b":true,"a":null}})
  end

  test "strings are escaped, and a newline survives a round trip" do
    assert Json.encode("a\nb\"c\\d") == ~s("a\\nb\\"c\\\\d")
    assert {:ok, "a\nb"} = Json.decode(Json.encode("a\nb"))
  end

  test "non-ASCII is kept as UTF-8" do
    assert Json.encode("héllo →") == ~s("héllo →")
  end

  test "lists and integers" do
    assert Json.encode([1, 2, 3]) == "[1,2,3]"
    assert Json.encode({:obj, [{"jobs", []}]}) == ~s({"jobs":[]})
  end

  test "decoding refuses what is not JSON, and what has bytes after the value" do
    assert {:error, _reason} = Json.decode("{")
    assert {:error, _reason} = Json.decode(~s({"a":1} and more))
    assert {:ok, %{"a" => 1}} = Json.decode(~s({"a":1}))
  end
end
