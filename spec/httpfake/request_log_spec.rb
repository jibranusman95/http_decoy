# frozen_string_literal: true

require "spec_helper"

RSpec.describe HttpFake::RequestLog do
  subject(:log) { described_class.new }

  let(:entry_attrs) do
    { method: "POST", path: "/charges", body: { amount: 100 }, headers: {}, query_params: {} }
  end

  describe "#record and #all" do
    it "stores a recorded entry" do
      log.record(**entry_attrs)
      expect(log.all.size).to eq 1
    end

    it "returns a dup — mutations don't affect the internal store" do
      log.record(**entry_attrs)
      log.all << :bad
      expect(log.all.size).to eq 1
    end
  end

  describe "#for" do
    before do
      log.record(method: "POST", path: "/charges",  body: {}, headers: {}, query_params: {})
      log.record(method: "GET",  path: "/charges",  body: {}, headers: {}, query_params: {})
      log.record(method: "POST", path: "/refunds",  body: {}, headers: {}, query_params: {})
    end

    it "filters by method and path" do
      entries = log.for("POST", "/charges")
      expect(entries.size).to eq 1
      expect(entries.first.http_method).to eq "POST"
      expect(entries.first.path).to eq "/charges"
    end

    it "is case-insensitive on method" do
      expect(log.for(:post, "/charges").size).to eq 1
    end
  end

  describe "#clear" do
    it "removes all entries" do
      log.record(**entry_attrs)
      log.clear
      expect(log.all).to be_empty
    end
  end

  describe "#count" do
    it "returns the number of recorded entries" do
      3.times { log.record(**entry_attrs) }
      expect(log.count).to eq 3
    end
  end

  describe "thread safety" do
    it "handles concurrent writes without data loss" do
      threads = 50.times.map do
        Thread.new { log.record(**entry_attrs) }
      end
      threads.each(&:join)
      expect(log.count).to eq 50
    end
  end
end
