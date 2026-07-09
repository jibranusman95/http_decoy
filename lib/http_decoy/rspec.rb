# frozen_string_literal: true

require "rspec/core"
require_relative "route_map"
require_relative "server"
require_relative "webmock_integration"
require_relative "definition"
require_relative "body_matcher"

module HttpDecoy
  # RSpec integration.
  #
  # Two equivalent usage patterns:
  #
  # Pattern A — inline (per describe block):
  #
  #   RSpec.describe MyService do
  #     include HttpDecoy::RSpec
  #
  #     fake_server(:payments) do
  #       post "/charges" do
  #         respond 201, json: { id: "ch_abc" }
  #       end
  #     end
  #
  #     it "creates a charge" do
  #       MyService.charge(100)
  #       expect(fake_server(:payments)).to have_received_request(:post, "/charges").once
  #     end
  #   end
  #
  # Pattern B — suite-wide definition (most common):
  #
  #   FakeStripe = HttpDecoy.define(:stripe) do
  #     base_url "https://api.stripe.com"
  #     post "/v1/charges" do
  #       respond 200, json: { id: "ch_123" }
  #     end
  #   end
  #
  #   RSpec.configure { |c| c.include FakeStripe.rspec_helpers }
  #
  #   it "charges the card" do
  #     StripeService.charge(500)
  #     expect(fake_server(:stripe)).to have_received_request(:post, "/v1/charges").once
  #   end
  #
  module RSpec
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Class-level macro. Evaluates the block into a RouteMap once at class-load
      # time, then registers before/after hooks for per-example server lifecycle.
      def fake_server(name, &)
        route_map = RouteMap.new
        route_map.instance_eval(&)
        _http_decoy_register(name, route_map)
      end

      # Internal: register before/after hooks for a pre-built RouteMap.
      # Called by both the inline macro and Definition#rspec_helpers.
      def _http_decoy_register(name, route_map)
        before(:each) do
          server = Server.new(route_map)
          server.start
          stub = WebMockIntegration.setup(server)

          @_http_decoy_servers       ||= {}
          @_http_decoy_webmock_stubs ||= {}
          @_http_decoy_servers[name]       = server
          @_http_decoy_webmock_stubs[name] = stub
        end

        after(:each) do
          server = @_http_decoy_servers&.[](name)
          stub   = @_http_decoy_webmock_stubs&.[](name)
          WebMockIntegration.teardown(stub)
          server&.stop
        end
      end
    end

    # Instance-level accessor — returns the live Server for this example.
    def fake_server(name)
      @_http_decoy_servers[name]
    end

    # Run a block with a named scenario active.
    # server_name defaults to the only server if exactly one is registered.
    def with_scenario(scenario_name, server_name = nil, &)
      name = server_name || begin
        servers = @_http_decoy_servers || {}
        raise ArgumentError, "server_name required when multiple fake servers are active" if servers.size > 1
        raise ArgumentError, "No fake servers are active" if servers.empty?

        servers.keys.first
      end

      server = @_http_decoy_servers[name]
      raise ArgumentError, "No fake server named #{name.inspect}" unless server

      server.with_scenario(scenario_name, &)
    end
  end

  # ---------------------------------------------------------------------------
  # RSpec matchers
  # ---------------------------------------------------------------------------

  ::RSpec::Matchers.define :have_received_request do |method, path|
    match do |server|
      entries = server.request_log.for(method, path)
      next false if entries.empty?
      next false if @times && entries.count != @times
      next false if @body_matcher && entries.none? { |e| HttpDecoy::BodyMatcher.matches?(e.body, @body_matcher) }

      true
    end

    chain :once do
      @times = 1
    end
    chain :twice do
      @times = 2
    end
    chain :times do |n|
      @times = n
    end

    chain :with do |body: nil|
      @body_matcher = body
    end

    failure_message do |server|
      entries = server.request_log.for(method, path)
      if entries.empty?
        "expected #{method.to_s.upcase} #{path} to have been received, but it was never called"
      elsif @times && entries.count != @times
        "expected #{method.to_s.upcase} #{path} to have been received #{@times} time(s), " \
          "but it was received #{entries.count} time(s)"
      else
        "expected #{method.to_s.upcase} #{path} body to match #{@body_matcher.inspect}, " \
          "but received: #{entries.map(&:body).inspect}"
      end
    end

    failure_message_when_negated do |_server|
      "expected #{method.to_s.upcase} #{path} not to have been received"
    end

    description do
      desc = "have received #{method.to_s.upcase} #{path}"
      desc += " #{@times} time(s)" if @times
      desc += " with body matching #{@body_matcher.inspect}" if @body_matcher
      desc
    end
  end

  # ---------------------------------------------------------------------------
  # Definition — returned by HttpDecoy.define
  # ---------------------------------------------------------------------------

  # Reopens Definition (see definition.rb) to add the RSpec-specific helper.
  class Definition
    # Returns an anonymous module. Include it in RSpec.configure to register
    # the server lifecycle for every example group in the suite.
    #
    #   RSpec.configure { |c| c.include FakeStripe.rspec_helpers }
    #
    def rspec_helpers
      definition = self

      Module.new do
        include HttpDecoy::RSpec

        # define_singleton_method closes over `definition` from the outer scope.
        # `def self.included` would NOT — def never captures outer locals.
        #
        # `extend` is required here: `include HttpDecoy::RSpec` above only ran
        # HttpDecoy::RSpec.included against *this anonymous module*, not against
        # `base` — Ruby's included hook does not cascade through nested includes.
        # Without this line, `RSpec.configure { |c| c.include Foo.rspec_helpers }`
        # used on its own raises NoMethodError on `_http_decoy_register`.
        define_singleton_method(:included) do |base|
          super(base)
          base.extend(HttpDecoy::RSpec::ClassMethods)
          base._http_decoy_register(definition.name, definition.route_map)
        end

        define_method(:_http_decoy_definition) { definition }
      end
    end
  end
end
