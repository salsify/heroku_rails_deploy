# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'heroku_rails_deploy/version'

Gem::Specification.new do |spec|
  spec.name          = 'heroku_rails_deploy'
  spec.version       = HerokuRailsDeploy::VERSION
  spec.authors       = ['Salsify, Inc']
  spec.email         = ['engineering@salsify.com']

  spec.summary       = 'Simple deployment of Rails app to Heroku'
  spec.description   = spec.summary
  spec.homepage      = 'https://github.com/salsify/heroku_rails_deploy'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'rails'

  spec.add_development_dependency 'bundler', '~> 1.12'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.4'
  spec.add_development_dependency 'salsify_rubocop', '~> 0.42.0'
  spec.add_development_dependency 'overcommit'

  spec.add_development_dependency 'rspec_junit_formatter', '0.2.2'
end
