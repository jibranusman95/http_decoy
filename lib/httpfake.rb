# frozen_string_literal: true

require_relative "httpfake/version"
require_relative "httpfake/configuration"
require_relative "httpfake/route"
require_relative "httpfake/route_map"
require_relative "httpfake/router"
require_relative "httpfake/request_log"
require_relative "httpfake/handler_context"
require_relative "httpfake/server"
require_relative "httpfake/webmock_integration"

module HttpFake
  class << self
    # Global configuration.
    #
    #   HttpFake.configure do |c|
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
    #   FakeStripe = HttpFake.define(:stripe) do
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
      require_relative "httpfake/rspec"
      route_map = RouteMap.new
      route_map.instance_eval(&)
      Definition.new(name, route_map)
    end
  end
end
