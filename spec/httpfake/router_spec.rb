# frozen_string_literal: true

require "spec_helper"

RSpec.describe HttpFake::Router do
  subject(:router) { route_map.router }

  let(:route_map) do
    HttpFake::RouteMap.new.tap do |m|
      m.get "/users" do
        respond 200, json: {}
      end
      m.get "/users/:id" do
        respond 200, json: {}
      end
      m.post "/users" do
        respond 201, json: {}
      end
      m.get "/users/:id/posts/:post_id" do
        respond 200, json: {}
      end
      m.post "/payments", scenario: :card_declined do
        respond 402, json: {}
      end
    end
  end

  describe "#match" do
    it "matches an exact path" do
      result = router.match("GET", "/users")
      expect(result).not_to be_nil
      expect(result.route.method).to eq "GET"
    end

    it "matches a path with a single param" do
      result = router.match("GET", "/users/42")
      expect(result).not_to be_nil
      expect(result.params[:id]).to eq "42"
    end

    it "matches a path with multiple params" do
      result = router.match("GET", "/users/7/posts/99")
      expect(result).not_to be_nil
      expect(result.params[:id]).to eq "7"
      expect(result.params[:post_id]).to eq "99"
    end

    it "distinguishes HTTP methods" do
      get_result  = router.match("GET",  "/users")
      post_result = router.match("POST", "/users")
      expect(get_result.route.method).to eq "GET"
      expect(post_result.route.method).to eq "POST"
    end

    it "returns nil for unknown paths" do
      expect(router.match("GET", "/unknown")).to be_nil
    end

    it "returns nil when method doesn't match" do
      expect(router.match("DELETE", "/users")).to be_nil
    end

    it "returns nil for partial path matches" do
      expect(router.match("GET", "/users/42/extra/segments")).to be_nil
    end

    context "with scenarios" do
      it "matches a scenario route" do
        result = router.match("POST", "/payments", scenario: :card_declined)
        expect(result).not_to be_nil
        expect(result.route.scenario).to eq :card_declined
      end

      it "does not match a scenario route when no scenario is active" do
        expect(router.match("POST", "/payments")).to be_nil
      end
    end
  end
end
