# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "seed_preparers", "legislators", "base")
require Rails.root.join("db", "seeds", "seed_preparers", "legislators", "congress_dot_gov")

# Checks that CongressDotGov#party caches its answer properly: the variable it
# reads to decide whether it already has one, and the variable it writes the
# answer into, must be the same one (@party).
RSpec.describe SeedPreparers::Legislators::CongressDotGov do
  let(:sway_locale) do
    SwayLocale.find_or_create_by!(city: "congress", state: "congress", country: "united_states")
  end

  let(:member_json) do
    {
      "bioguideId" => "A000001",
      "name" => "Adams, Test",
      "partyName" => "Democrat",
      "state" => "Maryland",
      "currentMember" => true,
      "terms" => {"item" => [{"chamber" => "House", "startYear" => 2023}]},
      "url" => "https://api.congress.gov/v3/member/A000001"
    }
  end

  subject(:preparer) { described_class.new(member_json, sway_locale) }

  describe "#party" do
    it "returns the correct party character" do
      result = preparer.party
      expect(result).to eq("D") # Democrat → "D"
    end

    it "memoizes — returns the same value on repeated calls without recomputing" do
      first_call = preparer.party
      second_call = preparer.party

      expect(first_call).to eq(second_call)
    end

    it "does NOT recompute on the second call (WR-04: @_party guard was dead)" do
      # Call once to fill the cache
      first_result = preparer.party

      # @lat: [[congress-dot-gov-preparer-party-memoization#Proving CongressDotGov.party actually memoizes]]
      allow(preparer).to receive(:json).and_return({})

      second_result = preparer.party
      expect(second_result).to eq(first_result),
        "Expected memoized value #{first_result.inspect} but got #{second_result.inspect} — " \
        "guard variable mismatch (@_party vs @party) means memo is dead"
    end
  end

  # Two answers the seeder needs before it may write, change or
  # delete a term row.
  describe "what the entry says about itself" do
    it "reports somebody the roster still lists as a current member" do
      expect(preparer.current_member?).to be(true)
    end

    it "reports somebody the roster no longer lists" do
      departed = described_class.new(member_json.merge("currentMember" => false), sway_locale)

      expect(departed.current_member?).to be(false)
    end

    # An entry with no such key predates this work, or came straight from
    # congress.gov. Treating it as current keeps the old behaviour.
    it "treats an entry that says nothing as a current member" do
      silent = described_class.new(member_json.except("currentMember"), sway_locale)

      expect(silent.current_member?).to be(true)
    end

    # congress.gov reports one entry per Congress. Only the roster the refresh
    # writes carries whole terms with real end dates, and only that list may
    # drive a correction or a deletion.
    it "does not call congress.gov's own terms a complete history" do
      expect(preparer.terms_from_history?).to be(false)
    end

    it "reads the mark the refresh writes on a full history" do
      # The shape the history source really writes: every term carries the year
      # it ended. member_json above carries congress.gov's own shape, which does
      # not.
      from_history = described_class.new(
        member_json.merge(
          "termsSource" => LegislatorsCache::CongressTermHistory::SOURCE_NAME,
          "terms" => {"item" => [
            {"chamber" => "House of Representatives", "startYear" => 2021, "endYear" => 2023},
            {"chamber" => "House of Representatives", "startYear" => 2023, "endYear" => 2025}
          ]}
        ),
        sway_locale
      )

      expect(from_history.terms_from_history?).to be(true)
    end

    # The mark alone is not enough. The seeder deletes stored terms this list
    # does not name, so one stray key in a hand-edited roster would be the only
    # thing standing between a senator's six-year term and being cut to two.
    it "refuses the mark when a term carries no end year" do
      mismarked = described_class.new(
        member_json.merge(
          "termsSource" => LegislatorsCache::CongressTermHistory::SOURCE_NAME,
          "terms" => {"item" => [
            {"chamber" => "Senate", "startYear" => 2021, "endYear" => 2027},
            {"chamber" => "Senate", "startYear" => 2023}
          ]}
        ),
        sway_locale
      )

      expect(mismarked.terms_from_history?).to be(false)
    end

    it "refuses the mark when the entry carries no terms at all" do
      empty = described_class.new(
        member_json.merge(
          "termsSource" => LegislatorsCache::CongressTermHistory::SOURCE_NAME,
          "terms" => {"item" => []}
        ),
        sway_locale
      )

      expect(empty.terms_from_history?).to be(false)
    end
  end
end
