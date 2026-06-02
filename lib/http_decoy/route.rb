# frozen_string_literal: true

module HttpDecoy
  # Represents a single declared route: method + path pattern + optional scenario.
  class Route
    attr_reader :method, :pattern, :scenario, :handler_block

    def initialize(method, pattern, scenario: nil, &block)
      @method       = method.to_s.upcase
      @pattern      = pattern
      @scenario     = scenario
      @handler_block = block
    end
  end
end
