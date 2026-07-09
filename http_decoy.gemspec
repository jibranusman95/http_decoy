# frozen_string_literal: true

require_relative "lib/http_decoy/version"

Gem::Specification.new do |spec|
  spec.name          = "http_decoy"
  spec.version       = HttpDecoy::VERSION
  spec.authors       = ["Jibran Usman"]
  spec.email         = ["jibran.usman@hotmail.com"]

  spec.summary       = "Declarative fake HTTP servers for RSpec/Minitest. Real server. Real requests. Zero cassettes."
  spec.description   = "http_decoy spins up a real Rack server inside your tests with a clean DSL. " \
                       "Define routes, validate request contracts, return dynamic fixtures, and tear down " \
                       "automatically. No VCR cassettes. No scattered WebMock stubs."
  spec.homepage      = "https://github.com/jibranusman95/http_decoy"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jibranusman95/http_decoy"
  spec.metadata["changelog_uri"]   = "https://github.com/jibranusman95/http_decoy/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) || f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end

  spec.require_paths = ["lib"]

  spec.add_dependency "rack",    ">= 2.0"
  spec.add_dependency "webrick", "~> 1.8"
end
