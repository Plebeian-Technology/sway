# frozen_string_literal: true

require "rails_helper"

# @lat: [[current-legislator-term#Why a Congress term is rebuilt from published history]]
RSpec.describe CongressRoster do
  let(:roster_file) do
    file = Tempfile.new(["roster", ".json"])
    file.write(roster_json.to_json)
    file.flush
    file
  end

  let(:roster_json) do
    [
      # Still in the Senate, first took the seat in 2013.
      {"bioguideId" => "SEN001", "terms" => {"item" => [{"startYear" => 2013, "chamber" => "Senate"}]}},
      # Moved from the House to the Senate in 2024.
      {"bioguideId" => "MOVE001", "terms" => {"item" => [
        {"startYear" => 2001, "endYear" => 2024, "chamber" => "House of Representatives"},
        {"startYear" => 2024, "chamber" => "Senate"}
      ]}},
      # An entry with no start year proves nothing.
      {"bioguideId" => "THIN001", "terms" => {"item" => [{"chamber" => "Senate"}]}}
    ]
  end

  subject(:roster) { described_class.new(Pathname.new(roster_file.path.to_s)) }

  after { roster_file.close! }

  describe "#title_in" do
    it "reads the chamber somebody was sitting in that year" do
      expect(roster.title_in("SEN001", 2025)).to eq("Sen.")
    end

    it "reads the chamber they were in BEFORE they moved, not the one they are in now" do
      expect(roster.title_in("MOVE001", 2010)).to eq("Rep.")
      expect(roster.title_in("MOVE001", 2025)).to eq("Sen.")
    end

    it "says nothing about a year before their service began" do
      expect(roster.title_in("SEN001", 2001)).to be_nil
    end

    # Only sitting members are listed, so somebody who has left office is
    # absent — and the caller must leave their rows alone rather than guess.
    it "says nothing about a member the roster does not carry" do
      expect(roster.title_in("GONE001", 2025)).to be_nil
    end

    it "says nothing about an entry with no start year" do
      expect(roster.title_in("THIN001", 2025)).to be_nil
    end
  end

  describe "#service_ended_in" do
    it "is nil while the stretch of service is still open" do
      expect(roster.service_ended_in("SEN001", 2025)).to be_nil
    end

    it "reports the year a closed stretch finished" do
      expect(roster.service_ended_in("MOVE001", 2010)).to eq(2024)
    end

    it "says nothing about a member the roster does not carry" do
      expect(roster.service_ended_in("GONE001", 2025)).to be_nil
    end
  end

  describe "the committed roster" do
    subject(:committed) { described_class.new }

    it "reads the file Sway ships" do
      expect(committed.title_in("W000817", 2025)).to eq("Sen.") # Elizabeth Warren
    end
  end
end
