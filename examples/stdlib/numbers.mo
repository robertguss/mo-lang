module Stdlib.Numbers
expose percent, parse_count

intent "Cross integer widths by name, give a float a fixed number of decimals, and read numbers out of text."

fn percent(part: UInt64, whole: UInt64) : String
  requires whole > 0

  (part.to_f64 / whole.to_f64 * 100.0).to_string(1)
end

fn parse_count(text: String) : Option(UInt32)
  case text.trim.to_u64
    Some(n): n.checked_to_u32
    None: None
  end
end

test "a named conversion crosses widths, and checked_ says when it cannot"
  assert 200.to_u8 == 200
  assert 65_535.checked_to_u16 is Some(65_535)
  assert 70_000.checked_to_u16 is None
  assert (0 - 1).checked_to_u64 is None
  assert 3.to_f64 == 3.0
end

test "a float rounds half away from zero on its decimal spelling"
  assert 2.675.round(2) == 2.68
  assert (0.0 - 2.5).round(0) == 0.0 - 3.0
  assert 1.25.to_string(1) == "1.3"
  assert 3.0.to_string(2) == "3.00"
  assert percent(1, 6) == "16.7"
end

test "text becomes a number only when it spells one"
  assert "42".to_u64 is Some(42)
  assert "-42".to_i64 == Some(0 - 42)
  assert "4_2".to_u64 is None
  assert "+1".to_u64 is None
  assert "18446744073709551616".to_u64 is None
  assert "2.5e3".to_f64 is Some(2500.0)
  assert ".5".to_f64 is None
  assert parse_count(" 12 ") is Some(12)
  assert parse_count("5000000000") is None
end

test rejects "a percent of nothing"
  percent(1, 0)
end
