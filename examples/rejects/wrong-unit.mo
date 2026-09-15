module Rejects.WrongUnit
expose waited

intent "A Duration is written with ms, seconds, minute, or days: any other name after an integer is refused when the program is checked, not when it runs (step 28)."

# expect MO0208: an integer has no field or function named second; a Duration is written with ms, seconds, minute, or days, as 10.seconds
fn waited() : Duration
  1.second
end
