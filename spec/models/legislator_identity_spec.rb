# frozen_string_literal: true

require "rails_helper"

# The rules for turning one roster entry into the value that
# identifies a person.
RSpec.describe LegislatorIdentity do
  describe ".from_published_id" do
    it "carries the published id through as the whole identity" do
      identity = described_class.from_published_id(described_class::BIOGUIDE, "M001226") #: LegislatorIdentity

      expect(identity.source).to eq("bioguide")
      expect(identity.value).to eq("M001226")
    end

    it "answers nil for an entry that published no id, because nothing else identifies it" do
      expect(described_class.from_published_id(described_class::OPENSTATES, nil)).to be_nil
      expect(described_class.from_published_id(described_class::OPENSTATES, "")).to be_nil
    end
  end

  describe ".seat_and_name" do
    it "pairs the seat with the name published under it" do
      identity = described_class.seat_and_name(
        seat: "baltimore-district-1",
        first_name: "Mark",
        last_name: "Parker"
      ) #: LegislatorIdentity

      expect(identity.source).to eq("seat_and_name")
      expect(identity.value).to eq("baltimore-district-1|mark-parker")
    end

    # A seat carrying the separator makes the pair unreadable, and .seat_from
    # has to read it back out to decide whether somebody is still in office.
    it "refuses a seat carrying the separator" do
      expect {
        described_class.seat_and_name(
          seat: "baltimore|district-1", first_name: "Mark", last_name: "Parker"
        )
      }.to raise_error(ArgumentError, /may not contain/)
    end

    # The pair is a KEY, not a name match. Two people on the same seat get two
    # values, which is what stops a successor being read as the person whose
    # votes are on that row.
    it "gives two occupants of one seat two different values" do
      parker = described_class.seat_and_name(
        seat: "baltimore-district-1", first_name: "Mark", last_name: "Parker"
      ) #: LegislatorIdentity
      successor = described_class.seat_and_name(
        seat: "baltimore-district-1", first_name: "Someone", last_name: "Else"
      ) #: LegislatorIdentity

      expect(parker.value).not_to eq(successor.value)
    end

    it "gives one person on two seats two different values, which a migration then maps" do
      councilman = described_class.seat_and_name(
        seat: "baltimore-district-1", first_name: "Zeke", last_name: "Cohen"
      ) #: LegislatorIdentity
      president = described_class.seat_and_name(
        seat: "baltimore-council-president", first_name: "Zeke", last_name: "Cohen"
      ) #: LegislatorIdentity

      expect(councilman.value).not_to eq(president.value)
    end

    it "folds punctuation and case out of the name, so a re-publish of the same name matches" do
      identity = described_class.seat_and_name(
        seat: "baltimore-district-5",
        first_name: "Isaac 'Yitzy'",
        last_name: "Schleifer"
      ) #: LegislatorIdentity

      expect(identity.value).to eq("baltimore-district-5|isaac-yitzy-schleifer")
    end

    it "folds accents rather than dropping the name" do
      identity = described_class.seat_and_name(
        seat: "baltimore-district-2", first_name: "José", last_name: "Núñez"
      ) #: LegislatorIdentity

      expect(identity.value).to eq("baltimore-district-2|jose-nunez")
    end

    # BaltimoreRefresh writes the Council President with a blank name on purpose
    # when Legistar cannot say who chairs the council, so that the office row
    # never disappears. An entry with no name cannot say who holds the seat.
    it "answers nil when the source published no name under the seat" do
      expect(
        described_class.seat_and_name(seat: "baltimore-council-president", first_name: "", last_name: "")
      ).to be_nil
    end

    it "answers nil when there is no seat" do
      expect(described_class.seat_and_name(seat: nil, first_name: "Mark", last_name: "Parker")).to be_nil
    end
  end

  # How the seeder says "the roster named this office but could not
  # fill it, so nobody has left it".
  describe ".seat_from" do
    it "gives back the seat half of a seat-and-name value" do
      expect(described_class.seat_from("baltimore-district-1|mark-parker"))
        .to eq("baltimore-district-1")
    end

    # A bioguide id is not a seat and must never answer as one.
    it "gives nothing for a value with no name half" do
      expect(described_class.seat_from("M000639")).to be_nil
      expect(described_class.seat_from("baltimore-district-1|")).to be_nil
      expect(described_class.seat_from(nil)).to be_nil
    end
  end

  describe "#==" do
    it "is equal on source and value together, and not on either alone" do
      identity = described_class.new(source: "bioguide", value: "M001226")

      expect(identity).to eq(described_class.new(source: "bioguide", value: "M001226"))
      expect(identity).not_to eq(described_class.new(source: "openstates", value: "M001226"))
      expect(identity).not_to eq(described_class.new(source: "bioguide", value: "M000639"))
    end
  end

  describe "#initialize" do
    it "refuses half an identity" do
      expect { described_class.new(source: "bioguide", value: "") }.to raise_error(ArgumentError)
      expect { described_class.new(source: "", value: "M001226") }.to raise_error(ArgumentError)
    end
  end
end
