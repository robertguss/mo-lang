module Types.Trait
expose Badge, Named, name
intent "Implement the single function promised by a small trait."

struct Badge
  text: String
end

trait Named
  fn name(badge: Badge) : String
end

impl Named for Badge
  fn name(badge: Badge) : String
    badge.text
  end
end

test "the implementation works as a dot call"
  badge = Badge(text: "Mo")
  assert badge.name == "Mo"
end
