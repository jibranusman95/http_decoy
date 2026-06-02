# frozen_string_literal: true

require "spec_helper"
require "net/http"

RSpec.describe HttpDecoy::Server do
  def make_server(&block)
    map = HttpDecoy::RouteMap.new
    map.instance_eval(&block)
    HttpDecoy::Server.new(map)
  end

  describe "lifecycle" do
    it "starts on a valid port and stops cleanly" do
      server = make_server { get("/ping") { respond 200, json: { ok: true } } }
      server.start
      expect(server.port).to be_between(1, 65_535)
      expect(server.base_url).to match(%r{http://127\.0\.0\.1:\d+})
      expect { server.stop }.not_to raise_error
    end

    it "assigns a different port to each instance" do
      s1 = make_server { get("/a") { respond 200, json: {} } }
      s2 = make_server { get("/b") { respond 200, json: {} } }
      s1.start
      s2.start
      expect(s1.port).not_to eq s2.port
    ensure
      s1.stop
      s2.stop
    end
  end

  describe "request handling" do
    subject(:server) do
      make_server do
        get "/ping" do
          respond 200, json: { pong: true }
        end

        get "/users/:id" do
          respond 200, json: { id: path_params[:id] }
        end

        post "/echo" do
          respond 200, json: { received: body }
        end
      end.tap(&:start)
    end

    after { server.stop }

    def http_get(server, path)
      uri = URI("#{server.base_url}#{path}")
      Net::HTTP.get_response(uri)
    end

    def http_post(server, path, payload)
      uri = URI("#{server.base_url}#{path}")
      Net::HTTP.post(uri, payload.to_json, "Content-Type" => "application/json")
    end

    it "responds to a matched GET route" do
      res = http_get(server, "/ping")
      expect(res.code).to eq "200"
      expect(JSON.parse(res.body)).to eq({ "pong" => true })
    end

    it "extracts path params and echoes them" do
      res = http_get(server, "/users/abc-42")
      expect(res.code).to eq "200"
      expect(JSON.parse(res.body)["id"]).to eq "abc-42"
    end

    it "returns 404 for unregistered routes" do
      res = http_get(server, "/unknown")
      expect(res.code).to eq "404"
    end

    it "parses and echoes JSON body" do
      res = http_post(server, "/echo", { amount: 500 })
      expect(JSON.parse(res.body)["received"]["amount"]).to eq 500
    end

    it "records requests in the log" do
      http_get(server, "/ping")
      expect(server.request_log.for("GET", "/ping").size).to eq 1
    end
  end

  describe "contract validation" do
    subject(:server) do
      make_server do
        post "/charges" do
          requires_body :amount, :currency
          validates :amount, type: Integer, min: 50
          respond 201, json: { id: "ch_123" }
        end
      end.tap(&:start)
    end

    after { server.stop }

    def post_charge(payload)
      uri = URI("#{server.base_url}/charges")
      Net::HTTP.post(uri, payload.to_json, "Content-Type" => "application/json")
    end

    it "returns 201 for a valid request" do
      res = post_charge({ amount: 100, currency: "usd" })
      expect(res.code).to eq "201"
    end

    it "returns 422 when a required field is missing" do
      res = post_charge({ amount: 100 })
      expect(res.code).to eq "422"
      expect(JSON.parse(res.body)["error"]).to match(/currency/)
    end

    it "returns 422 when validation fails" do
      res = post_charge({ amount: 10, currency: "usd" })
      expect(res.code).to eq "422"
      expect(JSON.parse(res.body)["error"]).to match(/amount/)
    end
  end

  describe "scenarios" do
    subject(:server) do
      make_server do
        post "/pay" do
          respond 200, json: { status: "ok" }
        end

        post "/pay", scenario: :declined do
          respond 402, json: { error: "card_declined" }
        end
      end.tap(&:start)
    end

    after { server.stop }

    def post_pay
      uri = URI("#{server.base_url}/pay")
      Net::HTTP.post(uri, "{}", "Content-Type" => "application/json")
    end

    it "uses the default route when no scenario is active" do
      res = post_pay
      expect(res.code).to eq "200"
    end

    it "uses the scenario route when a scenario is active" do
      server.with_scenario(:declined) do
        res = post_pay
        expect(res.code).to eq "402"
      end
    end

    it "reverts to the default route after the scenario block" do
      server.with_scenario(:declined) { post_pay }
      res = post_pay
      expect(res.code).to eq "200"
    end
  end

  describe "respond_sequence" do
    subject(:server) do
      make_server do
        get "/balance" do
          respond_sequence(
            [200, { json: { balance: 1000 } }],
            [200, { json: { balance:    0 } }],
            [403, { json: { error: "suspended" } }]
          )
        end
      end.tap(&:start)
    end

    after { server.stop }

    def fetch_balance
      Net::HTTP.get_response(URI("#{server.base_url}/balance"))
    end

    it "cycles through responses in order" do
      r1 = fetch_balance
      r2 = fetch_balance
      r3 = fetch_balance
      r4 = fetch_balance # wraps around

      expect(JSON.parse(r1.body)["balance"]).to eq 1000
      expect(JSON.parse(r2.body)["balance"]).to eq 0
      expect(r3.code).to eq "403"
      expect(JSON.parse(r4.body)["balance"]).to eq 1000
    end
  end
end
