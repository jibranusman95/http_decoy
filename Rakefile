# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/testtask"

RSpec::Core::RakeTask.new(:spec)

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  # Default -w flag surfaces a harmless "circular require" warning from
  # webmock/minitest loading against minitest's own loader — not our bug.
  t.warning = false
end

task default: %i[spec test]
