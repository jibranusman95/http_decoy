# frozen_string_literal: true

require_relative "route"
require_relative "router"

module HttpDecoy
  # DSL target for defining a set of routes.
  # Instantiated once at class-load time; immutable after definition.
  class RouteMap
    attr_reader :declared_base_url

    def initialize
      @routes = []
      @declared_base_url = nil
    end

    def base_url(url = nil)
      url ? @declared_base_url = url : @declared_base_url
    end

    %i[get post put patch delete head options].each do |verb|
      define_method(verb) do |pattern, scenario: nil, &block|
        @routes << Route.new(verb, pattern, scenario: scenario, &block)
      end
    end

    def routes
      @routes.dup
    end

    def router
      # Memoize — route list is never mutated after definition.
      @router ||= Router.new(@routes)
    end
  end
end
