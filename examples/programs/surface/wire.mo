module Surface.Wire
expose Request, spelled

intent "A module of the program that declares a Request of its own, which hides the stdlib's from this module's code only: main's requests to the surface still build the stdlib's (step 23)."

# A line main prints: a Request of this module's, which is not HTTP.
struct Request
  text: String
end

fn spelled(n: UInt64) : String
  Request(text: "the tally holds #{n}").text
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
