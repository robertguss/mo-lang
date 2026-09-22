module Find
expose Found, matcher_of, query_terms, found_in, eligible?, matches?

use Limits{excerpt, context}
use Model{Mode, Options, Matcher, BlockKind}
use Term{safe}

intent "Match one block at a time with ASCII-only case folding, and keep a bounded excerpt centred on the first match instead of the block's whole text."

# Which matcher terms occur in one block, and the terminal-safe excerpt around the first one.
struct Found
  flags: List(Bool)
  excerpt: String
end

fn matcher_of(options: Options) : Matcher
  terms = case options.mode
    Phrase: [options.query.to_lower]
    AllWords: query_terms(options.query)
  end
  Matcher(mode: options.mode, terms: terms, include_tools: options.include_tools)
end

# ASCII space, tab, LF, vertical tab, form feed, and CR delimit terms. Terms are lowered.
fn query_terms(query: String) : List(String)
  spaced = query.bytes.map(fn(byte) if separator?(byte): 32 else: byte end)
  normalized = String.from_bytes(spaced) or ""
  normalized.split(" ").filter(fn(word) word != "" end).map(fn(word) word.to_lower end)
end

fn separator?(byte: UInt8) : Bool
  byte == 32 or (byte >= 9 and byte <= 13)
end

fn eligible?(matcher: Matcher, kind: BlockKind) : Bool
  kind == Conversation or (matcher.include_tools and kind == Tool)
end

# A tool block is searched as its label, a newline, and its text, so a tool name can match.
# `to_lower` folds only ASCII letters, so grapheme positions in the lowered text are the text's.
fn found_in(matcher: Matcher, kind: BlockKind, label: String, text: String) : Option(Found)
  prefix = if kind == Tool: "#{label}\n" else: ""
  lowered = "#{prefix}#{text}".to_lower
  places = matcher.terms.map(fn(term) lowered.index_of(term) end)
  first = places.reduce(None, fn(best, place) earliest(best, place) end)
  case first
    None: None
    Some(at):
      start = at.saturating_sub(prefix.size).saturating_sub(context())
      Some(Found(flags: places.map(fn(place) place is Some(_) end), excerpt: window(text, start)))
  end
end

fn matches?(matcher: Matcher, flags: List(Bool)) : Bool
  flags.size == matcher.terms.size and flags.all?(fn(flag) flag end)
end

fn earliest(a: Option(UInt64), b: Option(UInt64)) : Option(UInt64)
  case (a, b)
    (Some(left), Some(right)): Some(min_of(left, right))
    (Some(left), None): Some(left)
    (None, Some(right)): Some(right)
    (None, None): None
  end
end

fn window(text: String, start: UInt64) : String
  clipped = text.slice(start, start + excerpt())
  before = if start > 0: "..." else: ""
  after = if text.size > start + excerpt(): "..." else: ""
  "#{before}#{safe(clipped)}#{after}"
end

fn phrase(query: String) : Matcher
  matcher_of(Options(query: query, dir: ".", mode: Phrase, include_tools: false, strict: false))
end

fn all_words(query: String) : Matcher
  matcher_of(Options(query: query, dir: ".", mode: AllWords, include_tools: true, strict: false))
end

test "all-words uses exactly the six ASCII whitespace bytes and lowers terms"
  assert query_terms("  one\ttwo\nTHREE\u{000B}four\u{000C}five\r ") == ["one",
    "two",
    "three",
    "four",
    "five"]
end

test "matching folds ASCII only, so non-ASCII stays exact"
  assert found_in(phrase("CONNECTION refused"), Conversation, "", "Connection Refused") is Some(_)
  assert found_in(phrase("É"), Conversation, "", "é") is None
  assert found_in(phrase("a.b["), Conversation, "", "x A.B[ y") is Some(_)
end

test "the excerpt is a window around the first match, marked where clipped"
  text = "#{"a".repeat(500)} needle #{"b".repeat(500)}"
  found = found_in(phrase("needle"), Conversation, "", text)
  assert found is Some(hit)
  assert hit.excerpt.starts_with?("...") and hit.excerpt.ends_with?("...")
  assert hit.excerpt.contains?("needle")
  assert hit.excerpt.size == 246
  short = found_in(phrase("needle"), Conversation, "", "a needle")
  assert short is Some(whole)
  assert whole.excerpt == "a needle"
end

test "all-words flags each term and a tool label can match"
  matcher = all_words("demo alpha zeta")
  found = found_in(matcher, Tool, "tool demo arguments", "{\"q\":\"alpha\"}")
  assert found is Some(hit)
  assert hit.flags == [true, true, false] and !matches?(matcher, hit.flags)
  assert matches?(matcher, [true, true, true])
  assert hit.excerpt == "{\"q\":\"alpha\"}"
end

test "tools are eligible only when requested"
  assert eligible?(phrase("x"), Conversation) and !eligible?(phrase("x"), Tool)
  assert eligible?(all_words("x"), Tool)
end

property "query terms are never empty and never hold an ASCII separator"
  for query in any(String)
    assert query_terms(query).all?(fn(term)
      term != "" and !term.bytes.any?(fn(byte)
        separator?(byte)
      end)
    end)
  end
end

verified: types, contracts, tests (6), property (200 seeds), sim (not run)
          proven: not run
