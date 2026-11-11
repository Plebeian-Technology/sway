# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::Congress::RollCallUnavailable do
  it "inherits from StandardError" do
    error = described_class.new(
      chamber: :house,
      congress: 119,
      session: 2,
      roll_call_number: 74,
      reason: "http_404"
    )
    expect(error).to be_a(StandardError)
  end

  it "exposes keyword arguments via readers" do
    error = described_class.new(
      chamber: :house,
      congress: 119,
      session: 2,
      roll_call_number: 74,
      reason: "http_404"
    )

    expect(error.chamber).to eq(:house)
    expect(error.congress).to eq(119)
    expect(error.session).to eq(2)
    expect(error.roll_call_number).to eq(74)
    expect(error.reason).to eq("http_404")
  end

  it "builds an exception message containing all attributes" do
    error = described_class.new(
      chamber: :house,
      congress: 119,
      session: 2,
      roll_call_number: 74,
      reason: "http_404"
    )

    expect(error.message).to eq("Roll call unavailable for house 119-2 #74: http_404")
  end

  context "when roll_call_number is nil" do
    it "exposes roll_call_number as nil" do
      nil_roll_call_error = described_class.new(
        chamber: :senate,
        congress: 118,
        session: 1,
        roll_call_number: nil,
        reason: "upstream_outage"
      )

      expect(nil_roll_call_error.roll_call_number).to be_nil
    end

    it "formats message cleanly without raising error" do
      nil_roll_call_error = described_class.new(
        chamber: :senate,
        congress: 118,
        session: 1,
        roll_call_number: nil,
        reason: "upstream_outage"
      )

      expect(nil_roll_call_error.message).to eq("Roll call unavailable for senate 118-1 #: upstream_outage")
    end
  end
end
