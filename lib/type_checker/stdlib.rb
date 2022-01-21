# TODO: this is *very* minimal, pinch a better one from RBS or something

module TypeChecker::Stdlib
    # `include` doesn't work because this is a Class
    E = TypeChecker::Environment
    MT = E::MethodType

    def self.add_types(environment)
        # Useful reference:
        # https://tiagodev.wordpress.com/2013/04/16/eigenclasses-for-lunch-the-ruby-object-model/

        environment.add_type E::DefinedType.new(
            path: "BasicObject",

            eigen: E::DefinedType.new(
                path: "<Eigen:BasicObject>",
                instance_methods: [
                    # TODO: `.new` should actually be "magic", and always have the same parameters
                    # as `#initialize`
                    E::Method.new(:new, [parse("() -> self")]),
                    E::Method.new(:initialize, [parse("() -> void")], visibility: :private),
                ]
            )
        )

        environment.add_type E::DefinedType.new(
            path: "Object",
            superclass: environment.types["BasicObject"],

            instance_methods: [
                E::Method.new(:inspect, [parse("() -> String")]),
            ]

            # Should get its `eigen` generated automatically by `DefinedType` constructor
        )

        environment.add_type E::DefinedType.new(
            path: "Module",
            superclass: environment.types["Object"],

            instance_methods: [
                # TODO: needs arrays, which don't exist yet
                E::Method.new(:nesting, [parse("() -> untyped")]),
            ]
        )

        environment.add_type E::DefinedType.new(
            path: "Class",
            superclass: environment.types["Module"],

            instance_methods: [
                E::Method.new(:superclass, [parse("() -> Class")]),
                E::Method.new(:new),
                E::Method.new(:initialize, visibility: :private),
            ]
        )

        environment.add_type E::DefinedType.new(
            path: "Numeric",
            superclass: environment.types["Object"],
        )

        environment.add_type E::DefinedType.new(
            path: "Integer",
            superclass: environment.types["Numeric"],
        )

        environment.add_type E::DefinedType.new(
            path: "String",
            superclass: environment.types["Object"],

            instance_methods: [
                E::Method.new(:length, [parse("() -> Integer")]),
            ]
        )

        # Yep, this is how it works...
        # https://tiagodev.wordpress.com/2013/04/16/eigenclasses-for-lunch-the-ruby-object-model/
        # We couldn't do this earlier because defining a class with a pending superclass doesn't
        # work yet, it throws an error on the eigen phase
        # TODO FIX - this will be a problem later!
        environment.types["BasicObject"].eigen.superclass = environment.types["Class"]

        environment.resolve_all_pending_types
    end

    private
    
    def self.parse(s)
        TypeChecker::Environment::TypeParser.parse_method_type(s)
    end
end
