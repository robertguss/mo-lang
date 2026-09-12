module Types.Trait
expose Describe, Book

intent "List the functions a type promises in a trait, and keep that promise in an impl."

trait Describe
  fn describe(item: Self) : String
end

struct Book
  title: String
  author: String
end

impl Describe for Book
  fn describe(item: Book) : String
    "#{item.title} by #{item.author}"
  end
end

test "the impl gives the type its describe"
  book = Book(title: "Dune", author: "Frank Herbert")
  assert book.describe == "Dune by Frank Herbert"
end
