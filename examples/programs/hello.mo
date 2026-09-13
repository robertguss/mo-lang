# run: Ada
module Programs.Hello
expose greeting

intent "Greet the name the program is given: the smallest main there is."

fn greeting(name: String) : String
  "Hello, #{name}!"
end

fn main(platform: Platform)
  name = platform.args.first or "world"
  platform.stdout.write("#{greeting(name)}\n")
end

test "greets the name it is given"
  assert greeting("Ada") == "Hello, Ada!"
end
