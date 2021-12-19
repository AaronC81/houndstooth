# TODO: this is *very* minimal, pinch a better one from RBS or something

module TypeChecker::Stdlib
    # `include` doesn't work because this is a Class
    E = TypeChecker::Environment

    def self.types
        basic_obj = E::DefinedType.new(
            path: "BasicObject",

            eigen: E::DefinedType.new(
                path: "<Eigen:BasicObject>",
                instance_methods: [
                    E::Method.new(:new),
                    E::Method.new(:initialize, visibility: :private),
                ]
            )
        )
        obj = E::DefinedType.new(
            path: "Object",
            superclass: basic_obj,

            instance_methods: [
                E::Method.new(:inspect),
            ]

            # Should get its `eigen` generated automatically by `DefinedType` constructor
        )

        mod = E::DefinedType.new(
            path: "Module",
            superclass: obj,

            instance_methods: [
                E::Method.new(:nesting),
            ]
        )

        cls = E::DefinedType.new(
            path: "Class",
            superclass: mod,

            instance_methods: [
                E::Method.new(:superclass),
                E::Method.new(:new),
                E::Method.new(:initialize, visibility: :private),
            ]
        )

        str = E::DefinedType.new(
            path: "String",
            superclass: obj,

            instance_methods: [
                E::Method.new(:length),
            ]
        )

        # Yep, this is how it works...
        # https://tiagodev.wordpress.com/2013/04/16/eigenclasses-for-lunch-the-ruby-object-model/
        # We couldn't do this earlier because we didn't have a class type yet!
        basic_obj.eigen.superclass = cls

        [basic_obj, obj, mod, cls, str]
    end
end
