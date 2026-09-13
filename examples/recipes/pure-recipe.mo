module Recipes.PureRecipe
expose Slug

intent "Publish a recipe whose implementation needs no capabilities at all."

recipe Slug
  intent "Turn a title into a lowercase, hyphen-joined URL slug"
  needs nothing
  fn slug(title: String) : String
    ensures result.size <= title.size
  end
  test "spaces become hyphens and capitals drop"
    assert slug("Hello World") == "hello-world"
  end
  test "an empty title gives an empty slug"
    assert slug("") == ""
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
