# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'active_record/pgcrypto/version'

Gem::Specification.new do |spec|
  spec.name          = "activerecord-pgcrypto"
  spec.version       = Activerecord::Pgcrypto::VERSION
  spec.authors       = ["jonathan schatz"]
  spec.email         = ["jon@divisionbyzero.com"]

  spec.summary       = %q{ActiveRecord attribute encryption via pgcrypto}
  spec.description   = %q{ActiveRecord attribute encryption via pgcrypto}
  spec.homepage      = "https://github.com/modosc/activerecord-pgcrypto"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency  'activesupport', '>= 4.0'
  spec.add_dependency  'activerecord', '>= 4.0'
  spec.add_dependency  'pg'
  spec.add_dependency  'arel', '~> 6.0'
  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency 'faker'
end
