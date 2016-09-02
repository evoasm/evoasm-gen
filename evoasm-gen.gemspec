# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'evoasm/gen/version'

Gem::Specification.new do |spec|
  spec.name          = "evoasm-gen"
  spec.version       = Evoasm::Gen::VERSION
  spec.authors       = ["Julian Aron Prenner (furunkel)"]
  spec.email         = ["furunkel@polyadic.com"]

  spec.summary       = %q{An AIMGP (Automatic Induction of Machine code by Genetic Programming) engine}
  spec.homepage      = "https://github.com/furunkel/evoasm-gen"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rake", "~> 10.0"
  spec.add_dependency "erubis", "~> 2.6"
  spec.add_dependency "gv", "~> 0.1"

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rubocop", "~> 0.41"
  spec.add_development_dependency "minitest-reporters", "~> 1.1"
  spec.add_development_dependency "ruby-prof", ">= 0.15"
end
