module Term
expose safe, safe_prefix, shell_word

intent "Render transcript-derived text readably on a terminal: printable Unicode passes, while controls and invisible formatting characters are shown as escapes."

# Printable ASCII passes and backslash doubles. LF, tab, and CR become \n, \t, and \r; other C0
# controls and DEL become \xNN. Non-ASCII text passes unless it is a C1 control, a bidi or
# zero-width format character, a line or paragraph separator, a BOM, an interlinear annotation, or
# a tag character; those become \u{XXXX}.
fn safe(text: String) : String
  bytes = text.bytes
  var parts = []
  var skip = 0
  for pair in bytes.enumerate
    if skip > 0
      skip = skip - 1
    else
      piece = escaped_at(bytes, pair.0, pair.1)
      parts = parts.push(piece.0)
      skip = piece.1
    end
  end
  String.join(parts, "")
end

fn safe_prefix(text: String, limit: UInt64) : String
  return safe(text) if text.size <= limit
  "#{safe(text.slice(0, limit))}..."
end

# A POSIX shell word for a value copied from a transcript: bare when every byte is plainly safe,
# otherwise single-quoted, each inner quote spelled '"'"' so no backslash is needed.
fn shell_word(text: String) : String
  plain = text != "" and text.bytes.all?(fn(byte) plain_byte?(byte) end)
  return safe(text) if plain
  quoted = text.replace("'", "'\"'\"'")
  safe("'#{quoted}'")
end

fn plain_byte?(byte: UInt8) : Bool
  letter = (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90)
  digit = byte >= 48 and byte <= 57
  letter or digit or "-_./:@%+=,".bytes.contains?(byte)
end

# The rendered text for the character starting at `at`, and how many more bytes it used.
fn escaped_at(bytes: List(UInt8), at: UInt64, byte: UInt8) : (String, UInt64)
  return (ascii_piece(byte), 0) if byte < 128
  width = utf8_width(byte)
  sequence = bytes.slice(at, at + width)
  point = code_point(sequence)
  shown = if hidden?(point): "\\u{#{hex(point, 4)}}" else: String.from_bytes(sequence) or "\u{FFFD}"
  (shown, width - 1)
end

fn ascii_piece(byte: UInt8) : String
  return "\\\\" if byte == 92
  return "\\n" if byte == 10
  return "\\t" if byte == 9
  return "\\r" if byte == 13
  return String.from_bytes([byte]) or "" if byte >= 32 and byte <= 126
  "\\x#{hex(byte.to_u64, 2)}"
end

fn utf8_width(lead: UInt8) : UInt64
  return 2 if lead < 224
  return 3 if lead < 240
  4
end

fn code_point(sequence: List(UInt8)) : UInt64
  lead = (sequence.first or 0).to_u64
  rest = sequence.drop(1).reduce(0, fn(sum, byte) sum * 64 + (byte.to_u64 % 64) end)
  top = case sequence.size
    2: lead % 32
    3: lead % 16
    _: lead % 8
  end
  top * pow64(sequence.size - 1) + rest
end

fn pow64(count: UInt64) : UInt64
  return 64 if count == 1
  return 4_096 if count == 2
  262_144
end

fn hidden?(point: UInt64) : Bool
  c1 = point <= 159
  bidi = point == 1_564 or (point >= 8_206 and point <= 8_207) or (point >= 8_234 and point <= 8_238)
  zero_width = (point >= 8_203 and point <= 8_205) or (point >= 8_288 and point <= 8_303)
  separators = point == 8_232 or point == 8_233
  special = point == 65_279 or (point >= 65_529 and point <= 65_531)
  tags = point >= 917_504 and point <= 917_631
  c1 or bidi or zero_width or separators or special or tags
end

fn hex(value: UInt64, width: UInt64) : String
  hex_digits(value).pad_left(width, "0")
end

fn hex_digits(value: UInt64) : String
  return "" if value == 0
  low = value % 16
  "#{hex_digits(value / 16)}#{"0123456789ABCDEF".slice(low, low + 1)}"
end

test "printable ASCII and ordinary Unicode prose pass unchanged"
  assert safe("Found it — café, naïve, 日本語, 🙂") == "Found it — café, naïve, 日本語, 🙂"
end

test "controls, DEL, and backslash are escaped"
  assert safe("a\u{001B}[31m\u{0000}\u{007F}\\z") == "a\\x1B[31m\\x00\\x7F\\\\z"
  assert safe("tab\there\nline\r") == "tab\\there\\nline\\r"
end

test "C1, bidi, zero-width, separator, BOM, and tag characters are escaped"
  assert safe("\u{0085}") == "\\u{0085}"
  assert safe("x\u{202E}y\u{2066}z") == "x\\u{202E}y\\u{2066}z"
  assert safe("\u{200B}\u{200D}\u{2028}\u{FEFF}") == "\\u{200B}\\u{200D}\\u{2028}\\u{FEFF}"
  assert safe("\u{061C}\u{E0041}") == "\\u{061C}\\u{E0041}"
end

test "prefixes clip by grapheme before escaping"
  assert safe_prefix("x".repeat(240), 240).size == 240
  assert safe_prefix("x".repeat(241), 240) == "#{"x".repeat(240)}..."
  assert safe_prefix("éé", 1) == "é..."
end

test "shell words are bare when plain and single-quoted otherwise"
  assert shell_word("/Users/x/my-project") == "/Users/x/my-project"
  assert shell_word("/tmp/two words") == "'/tmp/two words'"
  assert shell_word("it's $(rm)") == "'it'\"'\"'s $(rm)'"
  assert shell_word("") == "''"
end

property "safe output never holds a raw C0 control or DEL"
  for text in any(String)
    assert safe(text).bytes.all?(fn(byte) byte >= 32 and byte != 127 end)
  end
end

verified: types, contracts, tests (6), property (200 seeds), sim (not run)
          proven: not run
