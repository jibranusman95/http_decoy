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

    # Define a named fake service.
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
    #
    def define(name = :default, &)
      require_relative "http_decoy/rspec"
      route_map = RouteMap.new
      route_map.instance_eval(&)
      Definition.new(name, route_map)
    end
  end
end
