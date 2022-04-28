Gem::Specification.new do |s|
    s.name = "houndstooth"
    s.version = "0.1.0"
    s.authors = ["Aaron Christiansen"]
    s.email = ["aaronc20000@gmail.com"]
    s.homepage = "https://github.com/AaronC81/houndstooth"
    s.summary = "Experimental type checker"
    s.license = "MIT"
    s.files = `git ls-files`.split("\n")
    s.test_files = `git ls-files -- {test,spec,features}/*`.split("\n")
end
  