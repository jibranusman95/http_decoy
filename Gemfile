# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"

gem "webrick", "~> 1.8"

group :test do
  gem "minitest", "~> 5.24"
  gem "rack", ">= 2.0"
  gem "rack-test", "~> 2.1"
  gem "rspec", "~> 3.13"
  gem "simplecov", require: false
  gem "webmock", "~> 3.23"
end

group :lint do
  gem "rubocop", "~> 1.65", require: false
  gem "rubocop-rspec", "~> 3.0", require: false
end
