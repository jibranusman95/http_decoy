# frozen_string_literal: true

require "spec_helper"
require "net/http"

# Suite-wide definition — the primary usage pattern.
FakePayments = HttpDecoy.define(:payments) do
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

  get "/charges/:id" do
    respond 200, json: {
      id: -> { path_params[:id] },
      status: "succeeded"
    }
  end

  post "/charges", scenario: :card_declined do
    respond 402, json: { error: { code: "card_declined" } }
  end

  post "/charges", scenario: :timeout do
    raise_error :timeout
  end

  get "/balance" do
    respond_sequence(
      [200, { json: { available: 1000 } }],
      [200, { json: { available:    0 } }]
    )
  end
end

# Base URL matches the base_url declared in FakePayments.
# WebMock intercepts requests to this URL and routes them to the rack app.
PAYMENTS_URL = "https://payments.test.local"

RSpec.describe "http_decoy RSpec integration" do
  include HttpDecoy::RSpec
  include FakePayments.rspec_helpers

  def post_charge(payload = { amount: 100, currency: "usd" })
    uri = URI("#{PAYMENTS_URL}/charges")
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      req = Net::HTTP::Post.new(uri.path)
      req["Content-Type"] = "application/json"
      req.body = payload.to_json
      http.request(req)
    end
  end

  def get_charge(id)
    uri = URI("#{PAYMENTS_URL}/charges/#{id}")
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(Net::HTTP::Get.new(uri.path))
    end
  end

  describe "basic responses" do
    it "starts the server and serves defined routes" do
      res = post_charge
      expect(res.code).to eq "201"
    end

    it "returns dynamic content from the request body" do
      res  = post_charge(amount: 750, currency: "gbp")
      body = JSON.parse(res.body)
      expect(body["amount"]).to eq 750
      expect(body["currency"]).to eq "gbp"
    end

    it "generates a unique id for each request" do
      id1 = JSON.parse(post_charge.body)["id"]
      id2 = JSON.parse(post_charge.body)["id"]
      expect(id1).not_to eq id2
    end

    it "handles path params" do
      res  = get_charge("ch_abc123")
      body = JSON.parse(res.body)
      expect(body["id"]).to eq "ch_abc123"
    end
  end

  describe "contract enforcement" do
    it "rejects missing required fields with 422" do
      res = post_charge(amount: 100) # missing currency
      expect(res.code).to eq "422"
      expect(JSON.parse(res.body)["error"]).to include("currency")
    end

    it "rejects amounts below the minimum" do
      res = post_charge(amount: 10, currency: "usd")
      expect(res.code).to eq "422"
      expect(JSON.parse(res.body)["error"]).to include("amount")
    end
  end

  describe "scenarios" do
    it "uses the card_declined scenario" do
      with_scenario(:card_declined) do
        res = post_charge
        expect(res.code).to eq "402"
        expect(JSON.parse(res.body).dig("error", "code")).to eq "card_declined"
      end
    end

    it "restores the default route after the scenario block" do
      with_scenario(:card_declined) { post_charge }
      expect(post_charge.code).to eq "201"
    end

    it "simulates a timeout" do
      expect do
        with_scenario(:timeout) { post_charge }
      end.to raise_error(Timeout::Error)
    end
  end

  describe "respond_sequence" do
    it "returns responses in order across calls" do
      get = lambda do |path|
        uri = URI("#{PAYMENTS_URL}#{path}")
        Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(Net::HTTP::Get.new(uri.path)) }
      end

      r1 = get.call("/balance")
      r2 = get.call("/balance")

      expect(JSON.parse(r1.body)["available"]).to eq 1000
      expect(JSON.parse(r2.body)["available"]).to eq 0
    end
  end

  describe "request log and assertions" do
    it "records received requests" do
      post_charge
      expect(fake_server(:payments)).to have_received_request(:post, "/charges")
    end

    it "asserts call count with .once" do
      post_charge
      expect(fake_server(:payments)).to have_received_request(:post, "/charges").once
    end

    it "asserts call count with .times(n)" do
      3.times { post_charge }
      expect(fake_server(:payments)).to have_received_request(:post, "/charges").times(3)
    end

    it "fails the assertion when no request was made" do
      expect(fake_server(:payments)).not_to have_received_request(:post, "/charges")
    end

    it "isolates request logs between examples" do
      # No calls in this example — log should be clean
      expect(fake_server(:payments).request_log.count).to eq 0
    end
  end

  describe "inline fake_server macro" do
    include HttpDecoy::RSpec

    fake_server(:local) do
      get "/status" do
        respond 200, json: { healthy: true }
      end
    end

    it "works alongside the suite-wide definition" do
      local_server = fake_server(:local)
      res = Net::HTTP.get_response(URI("#{local_server.base_url}/status"))
      expect(res.code).to eq "200"
      expect(JSON.parse(res.body)["healthy"]).to be true
    end
  end
end
