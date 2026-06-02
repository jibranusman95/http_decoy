# frozen_string_literal: true

require "spec_helper"
require "rack/mock"

RSpec.describe HttpDecoy::HandlerContext do
  def make_request(method: "POST", path: "/charges", body: nil, content_type: "application/json", query: "")
    env = Rack::MockRequest.env_for(
      "#{path}?#{query}",
      method: method,
      input: body ? body.to_json : "",
      "CONTENT_TYPE" => content_type
    )
    Rack::Request.new(env)
  end

  subject(:ctx) do
    req = make_request(body: { amount: 500, currency: "usd" })
    described_class.new(req, { id: "ch_123" })
  end

  describe "#body" do
    it "parses JSON body as symbolized hash" do
      expect(ctx.body).to eq({ amount: 500, currency: "usd" })
    end

    it "returns empty hash for empty body" do
      req = make_request(body: nil)
      ctx = described_class.new(req, {})
      expect(ctx.body).to eq({})
    end

    it "parses form-encoded body" do
      env = Rack::MockRequest.env_for("/", method: "POST",
                                           input: "amount=100&currency=usd",
                                           "CONTENT_TYPE" => "application/x-www-form-urlencoded")
      req = Rack::Request.new(env)
      ctx = described_class.new(req, {})
      expect(ctx.body[:amount]).to eq "100"
    end
  end

  describe "#path_params" do
    it "exposes extracted path params" do
      expect(ctx.path_params[:id]).to eq "ch_123"
    end
  end

  describe "#query_params" do
    it "parses query string params" do
      req = make_request(query: "foo=bar&baz=1")
      ctx = described_class.new(req, {})
      expect(ctx.query_params[:foo]).to eq "bar"
    end
  end

  describe "#respond" do
    it "builds a valid Rack response tuple for JSON" do
      ctx.respond(200, json: { id: "ch_123" })
      status, headers, body_arr = ctx.response
      expect(status).to eq 200
      expect(headers["Content-Type"]).to eq "application/json"
      expect(JSON.parse(body_arr.first)).to eq({ "id" => "ch_123" })
    end

    it "builds a plain text response" do
      ctx.respond(204, text: "")
      status, headers, = ctx.response
      expect(status).to eq 204
      expect(headers["Content-Type"]).to eq "text/plain"
    end

    it "resolves lambdas in JSON bodies" do
      ctx.respond(200, json: { amount: -> { body[:amount] } })
      _, _, body_arr = ctx.response
      expect(JSON.parse(body_arr.first)["amount"]).to eq 500
    end

    it "merges extra headers" do
      ctx.respond(200, json: {}, headers: { "X-Custom" => "yes" })
      _, headers, = ctx.response
      expect(headers["X-Custom"]).to eq "yes"
    end
  end

  describe "#requires_body" do
    it "does not raise when all keys are present" do
      expect { ctx.requires_body(:amount, :currency) }.not_to raise_error
    end

    it "raises ContractError when a key is missing" do
      expect { ctx.requires_body(:amount, :payment_method) }
        .to raise_error(HttpDecoy::HandlerContext::ContractError, /payment_method/)
    end
  end

  describe "#validates" do
    it "passes when value matches type" do
      expect { ctx.validates(:amount, type: Integer) }.not_to raise_error
    end

    it "raises ContractError on type mismatch" do
      expect { ctx.validates(:currency, type: Integer) }
        .to raise_error(HttpDecoy::HandlerContext::ContractError, /currency/)
    end

    it "validates min" do
      expect { ctx.validates(:amount, min: 1000) }
        .to raise_error(HttpDecoy::HandlerContext::ContractError, /amount/)
    end

    it "validates inclusion" do
      expect { ctx.validates(:currency, inclusion: %w[gbp eur]) }
        .to raise_error(HttpDecoy::HandlerContext::ContractError, /currency/)
    end
  end

  describe "#respond_sequence" do
    it "returns first response on call_index 0" do
      ctx = described_class.new(make_request, {}, call_index: 0)
      ctx.respond_sequence(
        [200, { json: { n: 1 } }],
        [200, { json: { n: 2 } }]
      )
      _, _, body_arr = ctx.response
      expect(JSON.parse(body_arr.first)["n"]).to eq 1
    end

    it "returns second response on call_index 1" do
      ctx = described_class.new(make_request, {}, call_index: 1)
      ctx.respond_sequence(
        [200, { json: { n: 1 } }],
        [200, { json: { n: 2 } }]
      )
      _, _, body_arr = ctx.response
      expect(JSON.parse(body_arr.first)["n"]).to eq 2
    end

    it "wraps around on overflow" do
      ctx = described_class.new(make_request, {}, call_index: 2)
      ctx.respond_sequence(
        [200, { json: { n: 1 } }],
        [200, { json: { n: 2 } }]
      )
      _, _, body_arr = ctx.response
      expect(JSON.parse(body_arr.first)["n"]).to eq 1
    end
  end

  describe "#raise_error" do
    it "raises Timeout::Error for :timeout" do
      expect { ctx.raise_error(:timeout) }.to raise_error(Timeout::Error)
    end

    it "raises Errno::ECONNRESET for :reset" do
      expect { ctx.raise_error(:reset) }.to raise_error(Errno::ECONNRESET)
    end
  end
end
