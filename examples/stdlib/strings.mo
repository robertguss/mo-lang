module Stdlib.Strings
expose fields, masked

intent "Cut, search, and build text with the string rows, counting in graphemes."

fn fields(line: String) : List(String)
  line.split(" ").filter(fn(f) f != "" end)
end

fn masked(card: String) : String
  requires card.size >= 4

  last = card.slice(card.size - 4, card.size)
  last.pad_left(card.size, "*")
end

test "split keeps empty pieces, and lines drops a final newline and each CR"
  assert "a,,b".split(",") == ["a", "", "b"]
  assert "héllo".split("") == ["h", "é", "l", "l", "o"]
  assert "héllo".chars.size == 5
  assert "one\r\ntwo\n".lines == ["one", "two"]
  assert "".lines.size == 0
  assert "\n".lines == [""]
  assert fields("  GET  /a ") == ["GET", "/a"]
end

test "search and cut count graphemes, and their bounds clamp"
  word = "café au lait"
  assert word.index_of("au") is Some(5)
  assert word.index_of("tea") is None
  assert word.slice(0, 4) == "café"
  assert word.slice(10, 99) == "it"
  assert word.slice(8, 2) == ""
  assert word.starts_with?("café") and word.contains?(" au ") and word.ends_with?("lait")
end

test "text is built by replace, case, padding, repeat, trim, and join"
  assert "a-b-c".replace("-", ", ") == "a, b, c"
  assert "Mo lang".to_upper == "MO LANG"
  assert "ÉCOLE".to_lower == "École"
  assert "7".pad_left(3, "0") == "007"
  assert "ab".pad_right(4, ".") == "ab.."
  assert "toolong".pad_left(3, " ") == "toolong"
  assert "ab".repeat(3) == "ababab"
  assert "  \tpadded \n".trim == "padded"
  assert String.join(["x", "y", "z"], "/") == "x/y/z"
  assert masked("4111111111111111") == "************1111"
end

test "bytes become text only when they are UTF-8"
  assert String.from_bytes("café".bytes) is Some("café")
  assert String.from_bytes([99, 255]) is None
end

test rejects "a card too short to mask"
  masked("123")
end

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
