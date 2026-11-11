# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scraper::LegislatorVote do
  it "exposes all six readers" do
    v = Scraper::LegislatorVote.new(
      external_id: "1",
      support: "FOR",
      first_name: "Nick",
      last_name: "Mosby",
      party: "D",
      state_code: "MD"
    )
    expect(v.external_id).to eq("1")
    expect(v.support).to eq("FOR")
    expect(v.first_name).to eq("Nick")
    expect(v.last_name).to eq("Mosby")
    expect(v.party).to eq("D")
    expect(v.state_code).to eq("MD")
  end

  it "is a Data instance (frozen, value-equal)" do
    a = Scraper::LegislatorVote.new(external_id: "1", support: "FOR",
      first_name: "A", last_name: "B", party: "D", state_code: "MD")
    b = Scraper::LegislatorVote.new(external_id: "1", support: "FOR",
      first_name: "A", last_name: "B", party: "D", state_code: "MD")
    expect(a).to eq(b)
    expect(a).to be_frozen
  end
end
