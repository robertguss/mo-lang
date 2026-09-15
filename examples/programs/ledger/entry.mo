module Ledger.Entry
expose Kind, Posting, Account, Entry, blank, account_id, entry_id, number_in, kind_name, kind_named, clearing_of, clearing?, posted, shown_account, shown_entry, account_of, entry_of, whole_in, text_in

use Ledger.Money{Money, amount?, overdraft?, currency?, name?}

intent "What the ledger keeps: an account (a_ and a counter, a name, a currency, an overdraft), an entry (e_ and a counter, one of six kinds, its postings, the idempotency key that made it, when, and what it answers), the per-currency clearing account a capture credits, and the one JSON object each is both shown and stored as."

enum Kind
  Transfer
  Hold
  Capture
  Release
  Refund
  Settlement
end

# One side of an entry: a negative amount is a debit, a positive one a credit.
struct Posting
  account: String
  amount: Int64
end

# An account as it is opened; its balance is never kept here, only summed from the postings.
struct Account
  number: UInt64
  name: String
  currency: String
  overdraft: Money
  created_at: Time
end

# An entry. `account` is the account a hold, capture, release, or refund concerns ("" for a
# transfer and a settlement); `amount` what it moved, held, or released; `expires_at` a hold's,
# `hold` the hold a capture or release answers, `capture` the capture a refund answers,
# `reason` a release's, `day` a settlement's.
struct Entry
  number: UInt64
  kind: Kind
  postings: List(Posting)
  key: String
  at: Time
  account: String
  amount: Money
  expires_at: Option(Time)
  hold: Option(UInt64)
  capture: Option(UInt64)
  reason: Option(String)
  day: Option(String)
end

# An entry of the kind with nothing in it yet, for a rule to fill.
fn blank(number: UInt64, kind: Kind, key: String, at: Time) : Entry
  Entry(number: number, kind: kind, postings: [], key: key, at: at, account: "", amount: 0,
    expires_at: None, hold: None, capture: None, reason: None, day: None)
end

fn account_id(number: UInt64) : String
  "a_#{number}"
end

fn entry_id(number: UInt64) : String
  "e_#{number}"
end

# The number in an id written as the prefix and the number, one way only.
fn number_in(prefix: String, id: String) : Option(UInt64)
  return None if !id.starts_with?(prefix)
  n = try id.slice(prefix.size, id.size).to_u64
  return None if "#{prefix}#{n}" != id
  Some(n)
end

# The account a capture credits and a refund debits, one per currency.
fn clearing_of(currency: String) : String
  "clearing:#{currency}"
end

fn clearing?(id: String) : Bool
  id.starts_with?("clearing:")
end

# What the entry's postings sum to: 0 for every entry that creates or destroys no money.
fn posted(entry: Entry) : Int64
  entry.postings.map(fn(p) p.amount end).sum
end

fn kind_name(kind: Kind) : String
  case kind
    Transfer: "transfer"
    Hold: "hold"
    Capture: "capture"
    Release: "release"
    Refund: "refund"
    Settlement: "settlement"
  end
end

fn kind_named(name: String) : Option(Kind)
  case name
    "transfer": Some(Transfer)
    "hold": Some(Hold)
    "capture": Some(Capture)
    "release": Some(Release)
    "refund": Some(Refund)
    "settlement": Some(Settlement)
    _: None
  end
end

# An account as the API shows it and the store keeps it; the balance and available a record
# carries are what they were when it was written, and a replay never reads them.
fn shown_account(account: Account, balance: Int64, available: Int64) : String
  head = "{\"id\": \"#{account_id(account.number)}\", \"name\": #{Json.encode(account.name)}, \"currency\": \"#{account.currency}\""
  sums = "\"overdraft\": #{account.overdraft}, \"balance\": #{balance}, \"available\": #{available}"
  "#{head}, #{sums}, \"created_at\": #{Json.encode(account.created_at)}}"
end

# An entry as JSON, written by hand so ids read e_ and a_ and each kind carries only its fields.
fn shown_entry(entry: Entry) : String
  head = "{\"id\": \"#{entry_id(entry.number)}\", \"kind\": \"#{kind_name(entry.kind)}\"#{concern(entry)}"
  body = "\"postings\": #{Json.encode(entry.postings)}, \"key\": #{Json.encode(entry.key)}, \"at\": #{Json.encode(entry.at)}"
  "#{head}, #{body}#{tail(entry)}}"
end

fn concern(entry: Entry) : String
  case entry.kind
    Transfer: ", \"amount\": #{entry.amount}"
    Settlement: ""
    Hold | Capture | Release | Refund:
      ", \"account\": #{Json.encode(entry.account)}, \"amount\": #{entry.amount}"
  end
end

fn tail(entry: Entry) : String
  expires = optional("expires_at", entry.expires_at.map(fn(t) Json.encode(t) end))
  hold = optional("hold", entry.hold.map(fn(n) "\"#{entry_id(n)}\"" end))
  capture = optional("capture", entry.capture.map(fn(n) "\"#{entry_id(n)}\"" end))
  reason = optional("reason", entry.reason.map(fn(r) Json.encode(r) end))
  day = optional("day", entry.day.map(fn(d) Json.encode(d) end))
  "#{expires}#{hold}#{capture}#{reason}#{day}"
end

fn optional(name: String, value: Option(String)) : String
  case value
    Some(text): ", \"#{name}\": #{text}"
    None: ""
  end
end

# An account read back from its JSON, or None for text that is not one that keeps the rules.
fn account_of(text: String) : Option(Account)
  fields = try object_of(text)
  name = try text_in(fields, "name")
  currency = try text_in(fields, "currency")
  overdraft = try whole_in(fields, "overdraft")
  return None if !name?(name) or !currency?(currency) or !overdraft?(overdraft)
  Some(Account(number: try number_in("a_", try text_in(fields, "id")), name: name,
    currency: currency, overdraft: overdraft, created_at: try time_in(fields, "created_at")))
end

# An entry read back from its JSON, or None for text that is not an entry of a kind it names.
fn entry_of(text: String) : Option(Entry)
  fields = try object_of(text)
  kind = try kind_named(try text_in(fields, "kind"))
  number = try number_in("e_", try text_in(fields, "id"))
  var read = blank(number, kind, try text_in(fields, "key"), try time_in(fields, "at"))
  read.postings = try postings_in(fields)
  read.account = text_in(fields, "account") or ""
  read.day = text_in(fields, "day")
  read.reason = text_in(fields, "reason")
  read.expires_at = time_in(fields, "expires_at")
  read.hold = text_in(fields, "hold").map(fn(id) number_in("e_", id) or 0 end)
  read.capture = text_in(fields, "capture").map(fn(id) number_in("e_", id) or 0 end)
  amount = whole_in(fields, "amount") or 0
  return None if amount < 0 or read.hold == Some(0) or read.capture == Some(0)
  read.amount = amount
  Some(read)
end

fn postings_in(fields: Map(String, Json)) : Option(List(Posting))
  items = try items_of(try fields.get("postings"))
  read = items.flat_map(fn(item) posting_of(item) end)
  return None if read.size != items.size
  Some(read)
end

fn items_of(value: Json) : Option(List(Json))
  case value
    Array(list): Some(list)
    Object(_) | String(_) | Number(_) | Bool(_) | Null: None
  end
end

fn posting_of(item: Json) : List(Posting)
  case item
    Object(fields):
      case (text_in(fields, "account"), whole_in(fields, "amount"))
        (Some(account), Some(amount)): [Posting(account: account, amount: amount)]
        _: []
      end
    Array(_) | String(_) | Number(_) | Bool(_) | Null: []
  end
end

fn object_of(text: String) : Option(Map(String, Json))
  case Json.decode(text)
    Ok(Object(fields)): Some(fields)
    Ok(_): None
    Error(_): None
  end
end

fn text_in(fields: Map(String, Json), name: String) : Option(String)
  case fields.get(name)
    Some(String(text)): Some(text)
    Some(_): None
    None: None
  end
end

fn time_in(fields: Map(String, Json), name: String) : Option(Time)
  Time.parse(try text_in(fields, name))
end

# A whole number of either sign; a fraction, or anything but a number, is None.
fn whole_in(fields: Map(String, Json), name: String) : Option(Int64)
  value = try fields.get(name)
  value.to_i64
end

fn transfer_of(at: Time) : Entry
  var made = blank(3, Transfer, "k1", at)
  made.postings = [Posting(account: "a_1", amount: -1_500), Posting(account: "a_2", amount: 1_500)]
  made.amount = 1_500
  made
end

test "an id is its prefix and the number, written one way"
  assert account_id(7) == "a_7" and entry_id(12) == "e_12"
  assert number_in("a_", "a_7") == Some(7) and number_in("e_", "e_12") == Some(12)
  assert number_in("a_", "a_07") is None and number_in("a_", "e_7") is None
  assert number_in("e_", "e_") is None and number_in("e_", "e_1x") is None
  assert clearing_of("USD") == "clearing:USD" and clearing?("clearing:USD") and !clearing?("a_1")
end

test "a transfer's postings sum to zero, and it is shown with its amount and key"
  at = Time.fixture()
  made = transfer_of(at)
  assert posted(made) == 0
  assert shown_entry(made) == "{\"id\": \"e_3\", \"kind\": \"transfer\", \"amount\": 1500, \"postings\": [{\"account\": \"a_1\", \"amount\": -1500}, {\"account\": \"a_2\", \"amount\": 1500}], \"key\": \"k1\", \"at\": \"2026-01-01T00:00:00Z\"}"
end

test "each kind is shown with only its own fields"
  at = Time.fixture()
  var hold = blank(4, Hold, "h", at)
  hold.account = "a_1"
  hold.amount = 5_000
  hold.expires_at = Some(at + 60_000.ms)
  assert shown_entry(hold).ends_with?("\"key\": \"h\", \"at\": \"2026-01-01T00:00:00Z\", \"expires_at\": \"2026-01-01T00:01:00Z\"}")
  assert shown_entry(hold).contains?("\"account\": \"a_1\", \"amount\": 5000, \"postings\": []")
  var release = blank(5, Release, "", at)
  release.hold = Some(4)
  release.reason = Some("expired")
  assert shown_entry(release).ends_with?("\"hold\": \"e_4\", \"reason\": \"expired\"}")
  var settlement = blank(6, Settlement, "s", at)
  settlement.day = Some("2026-01-01")
  assert shown_entry(settlement) == "{\"id\": \"e_6\", \"kind\": \"settlement\", \"postings\": [], \"key\": \"s\", \"at\": \"2026-01-01T00:00:00Z\", \"day\": \"2026-01-01\"}"
  assert kind_named(kind_name(Refund)) == Some(Refund) and kind_named("payout") is None
end

test "an account and every kind of entry read back from their JSON"
  at = Time.fixture()
  ada = Account(number: 1, name: "ada", currency: "USD", overdraft: 500, created_at: at)
  assert account_of(shown_account(ada, -20, -70)) == Some(ada)
  assert shown_account(ada, -20,
    -70) == "{\"id\": \"a_1\", \"name\": \"ada\", \"currency\": \"USD\", \"overdraft\": 500, \"balance\": -20, \"available\": -70, \"created_at\": \"2026-01-01T00:00:00Z\"}"
  made = transfer_of(at)
  assert entry_of(shown_entry(made)) == Some(made)
  var capture = blank(8, Capture, "c", at + 1.minute)
  capture.account = "a_1"
  capture.amount = 4_200
  capture.hold = Some(4)
  capture.postings = [Posting(account: "a_1", amount: -4_200),
    Posting(account: "clearing:USD", amount: 4_200)]
  assert entry_of(shown_entry(capture)) == Some(capture)
  var refund = blank(9, Refund, "r", at)
  refund.capture = Some(8)
  refund.account = "a_1"
  refund.amount = 1
  assert entry_of(shown_entry(refund)) == Some(refund)
end

test "text that is not an account or an entry does not read back as one"
  at = Time.fixture()
  made = shown_entry(transfer_of(at))
  assert entry_of("not json") is None and entry_of("[1]") is None
  assert entry_of(made.replace("\"kind\": \"transfer\"", "\"kind\": \"payout\"")) is None
  assert entry_of(made.replace("\"id\": \"e_3\"", "\"id\": \"a_3\"")) is None
  assert entry_of(made.replace("\"amount\": -1500", "\"amount\": -1500.5")) is None
  assert entry_of(made.replace("\"amount\": 1500,", "\"amount\": -1,")) is None
  ada = Account(number: 1, name: "ada", currency: "USD", overdraft: 0, created_at: at)
  assert account_of(shown_account(ada, 0, 0).replace("USD", "usd")) is None
  assert account_of(shown_account(ada, 0, 0).replace("\"overdraft\": 0",
    "\"overdraft\": -1")) is None
end

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
