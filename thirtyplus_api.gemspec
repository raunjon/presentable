# frozen_string_literal: true

require_relative "lib/thirtyplus_api/version"

Gem::Specification.new do |spec|
  spec.name = "thirtyplus_api"
  spec.version = ThirtyplusApi::VERSION
  spec.authors = ["Raunak Joneja"]
  spec.summary = "Shared API envelope, field filtering, pagination and error helpers for ThirtyPlus Rails services"
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", "~> 7.1"
  spec.add_dependency "activerecord", "~> 7.1"
  spec.add_dependency "activesupport", "~> 7.1"
  spec.add_dependency "jwt", ">= 2.10", "< 4"
  spec.add_dependency "pagy", "~> 9.3"
  spec.add_dependency "railties", "~> 7.1"
end
