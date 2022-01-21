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
                superclass: E::PendingDefinedType.new("Class"),
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
            superclass: E::PendingDefinedType.new("BasicObject"),

            instance_methods: [
                E::Method.new(:inspect, [parse("() -> String")]),
            ]

            # Should get its `eigen` generated automatically by `DefinedType` constructor
        )

        environment.add_type E::DefinedType.new(
            path: "Module",
            superclass: E::PendingDefinedType.new("Object"),

            instance_methods: [
                # TODO: needs arrays, which don't exist yet
                E::Method.new(:nesting, [parse("() -> untyped")]),
            ]
        )

        environment.add_type E::DefinedType.new(
            path: "Class",
            superclass: E::PendingDefinedType.new("Module"),

            instance_methods: [
                E::Method.new(:superclass, [parse("() -> Class")]),
                E::Method.new(:new),
                E::Method.new(:initialize, visibility: :private),
            ]
        )

        environment.add_type E::DefinedType.new(
            path: "Numeric",
            superclass: E::PendingDefinedType.new("Object"),
        )

        environment.add_type E::DefinedType.new(
            path: "Integer",
            superclass: E::PendingDefinedType.new("Numeric"),
        )

        environment.add_type E::DefinedType.new(
            path: "String",
            superclass: E::PendingDefinedType.new("Object"),

            instance_methods: [
                E::Method.new(:length, [parse("() -> Integer")]),
            ]
        )

        environment.resolve_all_pending_types
    end

    private
    
    def self.parse(s)
        TypeChecker::Environment::TypeParser.parse_method_type(s)
    end
end
