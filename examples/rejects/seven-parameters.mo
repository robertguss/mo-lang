module Rejects.SevenParameters
expose label

intent "A function takes at most six parameters; a seventh does not compile, and a struct is the fix."

# expect MO0303: label takes 7 parameters and the limit is 6; group them in a struct.
fn label(name: String, street: String, city: String, region: String, postcode: String,
  country: String, phone: String) : String
  "#{name}, #{street}, #{city} #{region} #{postcode}, #{country}, #{phone}"
end

test "every part appears on the label"
  line = label("Ada", "1 Main St", "Springfield", "IL", "62701", "USA", "555-0100")
  assert line.starts_with?("Ada, 1 Main St")
end
