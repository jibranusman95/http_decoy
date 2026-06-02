# frozen_string_literal: true

module HttpDecoy
  # Matches an incoming (method, path) pair against a list of Route objects.
  # Supports :param segments in patterns, e.g. "/v1/charges/:id".
  class Router
    Match = Struct.new(:route, :params, keyword_init: true)

    def initialize(routes)
      @routes = routes
    end

    # Returns a Match or nil.
    def match(method, path, scenario: nil)
      http_method = method.to_s.upcase
      @routes.each do |route|
        next unless route.method == http_method
        next unless route.scenario == scenario

        captures = extract_params(route.pattern, path)
        next if captures.nil?

        return Match.new(route: route, params: captures)
      end
      nil
    end

    private

    def extract_params(pattern, path)
      regex = pattern_to_regex(pattern)
      m = path.match(regex)
      return nil unless m

      m.named_captures.transform_keys(&:to_sym)
    end

    def pattern_to_regex(pattern)
      escaped = pattern.gsub(/:([a-zA-Z_][a-zA-Z0-9_]*)/) { "(?<#{Regexp.last_match(1)}>[^/]+)" }
      /\A#{escaped}\z/
    end
  end
end
