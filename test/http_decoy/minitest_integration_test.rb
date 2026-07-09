# frozen_string_literal: true

require "test_helper"

# Suite-wide definition — mirrors spec/integration/rspec_integration_spec.rb
# so both frameworks are proven against the same DSL surface.
FakeMinitestPayments = HttpDecoy.define(:payments) do
  base_url "https://payments.test.local"

  post "/charges" do
    requires_body :amount, :currency
    validates :amount, type: Integer, min: 50

    respond 201, json: {
      id: -> { "ch_#{rand(100_000..999_999)}" },
      amount: -> { body[:amount] },
      currency: -> { body[:currency] },
      status: "succeeded"
    }
  end

  post "/charges", scenario: :card_declined do
    respond 402, json: { error: { code: "card_declined" } }
  end

  get "/balance" do
    respond_sequence(
      [200, { json: { available: 1000 } }],
      [200, { json: { available: 0 } }]
    )
  end
end

PAYMENTS_URL = "https://payments.test.local"

class MinitestIntegrationTest < Minitest::Test
  include FakeMinitestPayments.minitest_helpers

  def post_charge(payload = { amount: 100, currency: "usd" })
    uri = URI("#{PAYMENTS_URL}/charges")
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      req = Net::HTTP::Post.new(uri.path)
      req["Content-Type"] = "application/json"
      req.body = payload.to_json
      http.request(req)
    end
  end

  def test_starts_the_server_and_serves_defined_routes
    res = post_charge
    assert_equal "201", res.code
  end

  def test_returns_dynamic_content_from_the_request_body
    res  = post_charge(amount: 750, currency: "gbp")
    body = JSON.parse(res.body)
    assert_equal 750, body["amount"]
    assert_equal "gbp", body["currency"]
  end

  def test_rejects_amounts_below_the_minimum_with_unprocessable_entity
    res = post_charge(amount: 10, currency: "usd")
    assert_equal "422", res.code
  end

  def test_uses_the_card_declined_scenario
    with_scenario(:card_declined) do
      res = post_charge
      assert_equal "402", res.code
      assert_equal "card_declined", JSON.parse(res.body).dig("error", "code")
    end
  end

  def test_restores_the_default_route_after_the_scenario_block
    with_scenario(:card_declined) { post_charge }
    assert_equal "201", post_charge.code
  end

  def test_returns_responses_in_order_across_calls
    get = lambda do
      uri = URI("#{PAYMENTS_URL}/balance")
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(Net::HTTP::Get.new(uri.path)) }
    end

    r1 = get.call
    r2 = get.call

    assert_equal 1000, JSON.parse(r1.body)["available"]
    assert_equal 0, JSON.parse(r2.body)["available"]
  end

  def test_records_and_asserts_received_requests
    post_charge
    assert_received_request fake_server(:payments), :post, "/charges"
    assert_received_request fake_server(:payments), :post, "/charges", times: 1
  end

  def test_refutes_requests_that_were_never_made
    refute_received_request fake_server(:payments), :post, "/charges"
  end

  def test_isolates_request_logs_between_tests
    assert_equal 0, fake_server(:payments).request_log.count
  end
end

class MinitestInlineFakeServerTest < Minitest::Test
  include HttpDecoy::Minitest

  fake_server(:local) do
    get "/status" do
      respond 200, json: { healthy: true }
    end
  end

  def test_inline_macro_starts_its_own_server
    server = fake_server(:local)
    res = Net::HTTP.get_response(URI("#{server.base_url}/status"))
    assert_equal "200", res.code
    assert JSON.parse(res.body)["healthy"]
  end
end
