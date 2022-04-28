# Houndstooth

Houndstooth is a **highly-experimental Ruby static type checker**, which is uniquely
**metaprogramming-aware**.

Houndstooth was created for my final-year project at the University of York. It is far from
production-ready, and should be treated here as a proof-of-concept!

Here's an annotated example of what this enables you to do:

```ruby
#!var @name String
#!var @graduate Boolean
class Student
    #!arg String
    attr_reader :name

    # Now we'd like to define an accessor for our boolean variable, @graduate.
    # But we usually like methods returning a boolean to end in ?, so we can't
    # use `attr_accessor`.
    # Instead, let's define our own helper, `bool_accessor`

    #: (Symbol) -> void
    #!const required
    #  ^ This special annotation means, "hey, type checker - you need to check
    #    out what this does!"
    def self.bool_accessor(name)
        # Define our method #<name>?
        #!arg Boolean
        attr_reader "#{name}?".to_sym

        # ...and also define a normal writer, #<name>=
        #!arg Boolean
        attr_writer name
    end

    # Now use our neat new helper
    bool_accessor :graduate

    #: (String) -> void
    def initialize(name)
        @name = name
        @graduate = false
    end
end

# The type checker sees those `graduate?` and `graduate=` definitions, even
# though they were dynamic!
s = Student.new("Aaron")
s.graduate? # => false
s.graduate = true
s.graduate? # => true
```

It even understands control flow such as loops:

```ruby
class Adder
    1000.times do |i,|
        #!arg Integer
        #!arg Integer
        #  ^ These annotations are the parameter type (first one) and return
        #    type (second one)
        define_method :"add_#{i}" do |input,|
            i + input
        end
    end
end

# Now we can add to our heart's content
a = Adder.new
x = a.add_123(a.add_5(3))
```

Houndstooth includes a minimal Ruby interpreter capable of evaluating a pure and deterministic
subset of the language. Using this, it executes portions of your codebase to discover methods which
will be dynamically defined at runtime.

All methods can optionally be tagged, either as:

- _const_, which means they _can_ be executed by the interpreter. Such methods include `Integer#+`,
  `Array#each`, and `String#length`.
- _const-required_, which means they **must** be executed by the interpreter wherever they appear
  in your codebase. These are your metaprogramming methods, like `define_method` and `attr_reader`.

The strict requirements of const-required mean that Houndstooth's interpreter is guaranteed to
discover any invocations of metaprogramming, and therefore knows about the entire environment of
your program. 

Thanks to this tagging mechanism, it becomes a type error to write definitions which are not
guaranteed to exist at runtime, or depend on non-deterministic data:

```ruby
class A
    # This is a type error!
    # Cannot call non-const method `rand` on
    # `#<interpreter object: <Eigen:Kernel>>` from const context
    if Kernel.rand > 0.5
        #: () -> void
        def x; end
    end
end
```
