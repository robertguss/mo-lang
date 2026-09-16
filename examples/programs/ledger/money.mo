module Ledger.Money
expose Money, amount?, overdraft?, currency?, name?, reason?, key?, ttl_ms?, card_run?, day?

intent "What an amount of money is and the rules every field that names or measures it keeps: an amount is an Int64 of minor units, never a float, above zero and at most a trillion; a currency is three uppercase letters; a name, a reason, and an idempotency key each keep their bytes and never hold a run of 16 digits, which could be a card number; a hold lives 100 ms to a day; a day is YYYY-MM-DD."

# An amount in minor units: cents for USD. A posting's signed amount is an Int64 beside it.
type Money = Int64 where value >= 0

# An amount moved, held, captured, or refunded: above zero and at most 10^12 minor units, so
# the sum of every balance fits an Int64 whatever the traffic.
fn amount?(n: Int64) : Bool
  n >= 1 and n <= 1_000_000_000_000
end

# How far below zero an account may go: 0 to 10^12 minor units.
fn overdraft?(n: Int64) : Bool
  n >= 0 and n <= 1_000_000_000_000
end

# Three uppercase ASCII letters.
fn currency?(text: String) : Bool
  return false if text.byte_size != 3
  text.bytes.all?(fn(b) b >= 65 and b <= 90 end)
end

# 1 to 64 bytes of letters, digits, - and _, with no run of 16 digits.
fn name?(text: String) : Bool
  return false if text == "" or text.byte_size > 64
  return false if card_run?(text)
  text.bytes.all?(fn(b) named?(b) end)
end

fn named?(b: UInt8) : Bool
  return true if b >= 48 and b <= 57
  return true if b >= 65 and b <= 90
  return true if b >= 97 and b <= 122
  b == 45 or b == 95
end

fn digit?(b: UInt8) : Bool
  b >= 48 and b <= 57
end

# A release's reason: 1 to 256 bytes of UTF-8 with no control character and no run of 16 digits.
fn reason?(text: String) : Bool
  return false if text == "" or text.byte_size > 256
  return false if card_run?(text)
  plain?(text)
end

# An idempotency key: 1 to 128 bytes with no control character, and no run of 16 digits, since
# the entry it makes carries it.
fn key?(text: String) : Bool
  return false if text == "" or text.byte_size > 128
  return false if card_run?(text)
  plain?(text)
end

fn plain?(text: String) : Bool
  text.bytes.all?(fn(b) b >= 32 and b != 127 end)
end

# How long a hold lives before it expires: 100 ms to a day.
fn ttl_ms?(n: Int64) : Bool
  n >= 100 and n <= 86_400_000
end

# Whether the text holds 16 ASCII digits in a row, which could be a card number.
fn card_run?(text: String) : Bool
  text.bytes.reduce(0, fn(run, b) next_run(run, b) end) >= 16
end

# The digits in a row so far, kept at 16 once it gets there.
fn next_run(run: UInt64, b: UInt8) : UInt64
  return 16 if run >= 16
  return run + 1 if digit?(b)
  0
end

# A day is YYYY-MM-DD, a date that exists.
fn day?(text: String) : Bool
  digits = text.bytes
  return false if digits.size != 10
  return false if (digits.get(4) or 0) != 45 or (digits.get(7) or 0) != 45
  return false if !digits.all?(fn(b) digit?(b) or b == 45 end)
  year = text.slice(0, 4).to_u64 or 0
  month = text.slice(5, 7).to_u64 or 0
  day = text.slice(8, 10).to_u64 or 0
  return false if month < 1 or month > 12 or day < 1
  return day <= 31 if [1, 3, 5, 7, 8, 10, 12].contains?(month)
  return day <= 30 if month != 2
  leap = (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
  if leap: day <= 29 else: day <= 28
end

test "an amount is 1 to 10^12, and an overdraft 0 to 10^12"
  assert amount?(1) and amount?(1_000_000_000_000)
  assert !amount?(0) and !amount?(-5) and !amount?(1_000_000_000_001)
  assert overdraft?(0) and overdraft?(1_000_000_000_000) and !overdraft?(-1)
end

test "a currency is three uppercase letters, and a name keeps its bytes"
  assert currency?("USD") and currency?("EUR")
  assert !currency?("usd") and !currency?("US") and !currency?("USDT") and !currency?("U1D")
  assert name?("ada") and name?("a-b_C9") and name?("n".repeat(64))
  assert !name?("") and !name?("n".repeat(65)) and !name?("a b") and !name?("é")
end

test "a run of 16 digits is refused in a name, a reason, and a key, and 15 are not"
  assert card_run?("x4242424242424242") and card_run?("4242424242424242y")
  assert !card_run?("424242424242424") and !card_run?("4242 4242 4242 4242")
  assert !name?("ada4242424242424242") and name?("ada424242424242424")
  assert !reason?("card 4111111111111111") and reason?("card ending 1111")
  assert !key?("k-4111111111111111") and key?("k-1")
end

test "a reason and a key are plain text of bounded size, a hold's ttl 100 ms to a day"
  assert reason?("customer asked") and !reason?("") and !reason?("r".repeat(257))
  assert !reason?("a\nb") and reason?("naïve")
  assert key?("k".repeat(128)) and !key?("k".repeat(129)) and !key?("") and !key?("a\tb")
  assert ttl_ms?(100) and ttl_ms?(86_400_000) and !ttl_ms?(99) and !ttl_ms?(86_400_001)
end

test "a day is a date that exists"
  assert day?("2026-09-14") and day?("2028-02-29")
  assert !day?("2026-02-30") and !day?("2026-9-14") and !day?("today") and !day?("2026-09-14T")
end

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
