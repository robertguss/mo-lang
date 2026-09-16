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
  # body gone; regenerate
end

fn account_id(number: UInt64) : String
  # body gone; regenerate
end

fn entry_id(number: UInt64) : String
  # body gone; regenerate
end

# The number in an id written as the prefix and the number, one way only.
fn number_in(prefix: String, id: String) : Option(UInt64)
  # body gone; regenerate
end

# The account a capture credits and a refund debits, one per currency.
fn clearing_of(currency: String) : String
  # body gone; regenerate
end

fn clearing?(id: String) : Bool
  # body gone; regenerate
end

# What the entry's postings sum to: 0 for every entry that creates or destroys no money.
fn posted(entry: Entry) : Int64
  # body gone; regenerate
end

fn kind_name(kind: Kind) : String
  # body gone; regenerate
end

fn kind_named(name: String) : Option(Kind)
  # body gone; regenerate
end

# An account as the API shows it and the store keeps it; the balance and available a record
# carries are what they were when it was written, and a replay never reads them.
fn shown_account(account: Account, balance: Int64, available: Int64) : String
  # body gone; regenerate
end

# An entry as JSON, written by hand so ids read e_ and a_ and each kind carries only its fields.
fn shown_entry(entry: Entry) : String
  # body gone; regenerate
end

fn concern(entry: Entry) : String
  # body gone; regenerate
end

fn tail(entry: Entry) : String
  # body gone; regenerate
end

fn optional(name: String, value: Option(String)) : String
  # body gone; regenerate
end

# An account read back from its JSON, or None for text that is not one that keeps the rules.
fn account_of(text: String) : Option(Account)
  # body gone; regenerate
end

# An entry read back from its JSON, or None for text that is not an entry of a kind it names.
fn entry_of(text: String) : Option(Entry)
  # body gone; regenerate
end

fn postings_in(fields: Map(String, Json)) : Option(List(Posting))
  # body gone; regenerate
end

fn items_of(value: Json) : Option(List(Json))
  # body gone; regenerate
end

fn posting_of(item: Json) : List(Posting)
  # body gone; regenerate
end

fn object_of(text: String) : Option(Map(String, Json))
  # body gone; regenerate
end

fn text_in(fields: Map(String, Json), name: String) : Option(String)
  # body gone; regenerate
end

fn time_in(fields: Map(String, Json), name: String) : Option(Time)
  # body gone; regenerate
end

# A whole number of either sign; a fraction, or anything but a number, is None.
fn whole_in(fields: Map(String, Json), name: String) : Option(Int64)
  # body gone; regenerate
end

fn transfer_of(at: Time) : Entry
  # body gone; regenerate
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
