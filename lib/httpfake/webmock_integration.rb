# frozen_string_literal: true

module HttpFake
  # Manages the WebMock stub that routes a declared base_url to the server's Rack app.
  #
  # Auto-detect: if WebMock is loaded and HttpFake.configuration.auto_intercept is true,
  # requests to the declared base_url are intercepted transparently.
  #
  # Teardown removes only the stub httpfake created — never calls WebMock.reset!.
  # If WebMock/RSpec has already cleared the registry (its own after(:each) hook),
  # we rescue silently rather than crashing.
  module WebMockIntegration
    class << self
      def available?
        defined?(WebMock) && WebMock.respond_to?(:stub_request)
      end

      # Install an interception stub for the given server.
      # Returns the stub object so it can be removed precisely during teardown.
      def setup(server)
        return nil unless available? && HttpFake.configuration.auto_intercept
        return nil unless server.route_map.declared_base_url

        # Match the full base URL (scheme + host) so the regex anchors correctly.
        # e.g. "https://api.stripe.com" → /\Ahttps:\/\/api\.stripe\.com/
        base    = server.route_map.declared_base_url.chomp("/")
        pattern = /\A#{Regexp.escape(base)}/

        WebMock.stub_request(:any, pattern).to_rack(server.rack_app)
      end

      # Remove only the stub we created.
      # Rescues silently if webmock/rspec already cleared the registry between examples.
      def teardown(stub)
        return unless stub && available?

        WebMock::StubRegistry.instance.remove_request_stub(stub)
      rescue RuntimeError
        # Already removed by WebMock.reset! (e.g. webmock/rspec after(:each) hook). Fine.
      end
    end
  end
end
