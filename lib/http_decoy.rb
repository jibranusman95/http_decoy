# frozen_string_literal: true

require_relative "http_decoy/version"
require_relative "http_decoy/configuration"
require_relative "http_decoy/route"
require_relative "http_decoy/route_map"
require_relative "http_decoy/router"
require_relative "http_decoy/request_log"
require_relative "http_decoy/handler_context"
require_relative "http_decoy/server"
require_relative "http_decoy/webmock_integration"
require_relative "http_decoy/definition"

module HttpDecoy
  class << self
    # Global configuration.
    #
    #   HttpDecoy.configure do |c|
    #     c.auto_intercept = false   # opt out of WebMock auto-interception
    #   end
    def configure
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    # Define a named fake service, reusable across RSpec and Minitest.
    #
    #   FakeStripe = HttpDecoy.define(:stripe) do
    #     base_url "https://api.stripe.com"
    #
    #     post "/v1/charges" do
    #       requires_body :amount, :currency, :payment_method
    #       respond 200, json: { id: -> { "ch_#{SecureRandom.hex(8)}" } }
    #     end
    #   end
    #
    #   RSpec.configure { |c| c.include FakeStripe.rspec_helpers }
    #   # or, in a Minitest::Test subclass:
    #   include FakeStripe.minitest_helpers
    #
    # #rspec_helpers requires "http_decoy/rspec" to be loaded; #minitest_helpers
    # requires "http_decoy/minitest" — this method itself pulls in neither, so
    # a Minitest-only project never loads RSpec (and vice versa).
    def define(name = :default, &)
      route_map = RouteMap.new
      route_map.instance_eval(&)
      Definition.new(name, route_map)
    end
  end
end
