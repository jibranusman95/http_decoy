# frozen_string_literal: true

require_relative "route_map"
require_relative "server"
require_relative "webmock_integration"
require_relative "definition"
require_relative "body_matcher"

module HttpDecoy
  # Minitest integration. Same server lifecycle and semantics as
  # HttpDecoy::RSpec (fresh Server per test, WebMock stub scoped to that
  # server, teardown never calls WebMock.reset!) hooked into Minitest's
  # setup/teardown instead of RSpec's before/after.
  #
  # Pattern A — inline (per test class):
  #
  #   class ChargeTest < Minitest::Test
  #     include HttpDecoy::Minitest
  #
  #     fake_server(:payments) do
  #       post "/charges" do
  #         respond 201, json: { id: "ch_abc" }
  #       end
  #     end
  #
  #     def test_creates_a_charge
  #       MyService.charge(100)
  #       assert_received_request fake_server(:payments), :post, "/charges"
  #     end
  #   end
  #
  # Pattern B — suite-wide definition (shared with RSpec):
  #
  #   FakeStripe = HttpDecoy.define(:stripe) do
  #     base_url "https://api.stripe.com"
  #     post "/v1/charges" do
  #       respond 200, json: { id: "ch_123" }
  #     end
  #   end
  #
  #   class ChargeTest < Minitest::Test
  #     include FakeStripe.minitest_helpers
  #
  #     def test_charges_the_card
  #       StripeService.charge(500)
  #       assert_received_request fake_server(:stripe), :post, "/v1/charges"
  #     end
  #   end
  module Minitest
    def self.included(base)
      base.extend(ClassMethods)
      base.include(Assertions)
    end

    module ClassMethods
      # Class-level macro. Evaluates the block into a RouteMap once at class-load
      # time, then registers it for the shared setup/teardown hooks.
      def fake_server(name, &)
        route_map = RouteMap.new
        route_map.instance_eval(&)
        _http_decoy_register(name, route_map)
      end

      # Internal: register a pre-built RouteMap and install setup/teardown
      # (once per class) that start/stop every registered server.
      # Called by both the fake_server macro and Definition#minitest_helpers.
      def _http_decoy_register(name, route_map)
        _http_decoy_route_maps[name] = route_map
        _http_decoy_install_hooks
      end

      def _http_decoy_route_maps
        @_http_decoy_route_maps ||= {}
      end

      def _http_decoy_install_hooks
        return if @_http_decoy_hooks_installed

        @_http_decoy_hooks_installed = true

        define_method(:setup) do
          super()
          @_http_decoy_servers       = {}
          @_http_decoy_webmock_stubs = {}

          self.class._http_decoy_route_maps.each do |server_name, route_map|
            server = Server.new(route_map)
            server.start
            stub = WebMockIntegration.setup(server)
            @_http_decoy_servers[server_name] = server
            @_http_decoy_webmock_stubs[server_name] = stub
          end
        end

        define_method(:teardown) do
          (@_http_decoy_servers || {}).each_key do |server_name|
            server = @_http_decoy_servers[server_name]
            stub   = @_http_decoy_webmock_stubs[server_name]
            WebMockIntegration.teardown(stub)
            server&.stop
          end
          super()
        end
      end
    end

    # Instance-level accessor — returns the live Server for this test.
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

    # ---------------------------------------------------------------------------
    # Minitest assertions
    # ---------------------------------------------------------------------------
    module Assertions
      def assert_received_request(server, method, path, times: nil, body: nil)
        entries     = server.request_log.for(method, path)
        description = "#{method.to_s.upcase} #{path}"

        if times
          assert_equal times, entries.count,
                       "expected #{description} to have been received #{times} time(s), " \
                       "but it was received #{entries.count} time(s)"
        else
          assert entries.any?, "expected #{description} to have been received, but it was never called"
        end

        return unless body

        assert entries.any? { |e| HttpDecoy::BodyMatcher.matches?(e.body, body) },
               "expected #{description} body to match #{body.inspect}, but received: #{entries.map(&:body).inspect}"
      end

      def refute_received_request(server, method, path)
        entries = server.request_log.for(method, path)
        assert entries.empty?, "expected #{method.to_s.upcase} #{path} not to have been received"
      end
    end
  end

  # Reopens Definition (see definition.rb) to add the Minitest-specific helper.
  class Definition
    # Returns an anonymous module. Include it in a Minitest::Test subclass to
    # register the server lifecycle for every test in that class.
    #
    #   include FakeStripe.minitest_helpers
    #
    def minitest_helpers
      definition = self

      Module.new do
        include HttpDecoy::Minitest

        # See the matching comment in rspec.rb — the explicit `extend` is
        # required because Ruby's `included` hook does not cascade through
        # nested includes.
        define_singleton_method(:included) do |base|
          super(base)
          base.extend(HttpDecoy::Minitest::ClassMethods)
          base.include(HttpDecoy::Minitest::Assertions)
          base._http_decoy_register(definition.name, definition.route_map)
        end

        define_method(:_http_decoy_definition) { definition }
      end
    end
  end
end
