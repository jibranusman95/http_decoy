# frozen_string_literal: true

module HttpDecoy
  # Wraps a named RouteMap so it can be shared across multiple test files
  # and reused across test frameworks.
  #
  # Framework-specific helper methods are added by whichever integration
  # file is loaded: `require "http_decoy/rspec"` adds #rspec_helpers,
  # `require "http_decoy/minitest"` adds #minitest_helpers.
  class Definition
    attr_reader :name, :route_map

    def initialize(name, route_map)
      @name      = name
      @route_map = route_map
    end
  end
end
