# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislator-term-write-guard-history#Why term writing must not sit behind the guard]]
RSpec.describe "the committed Congress roster" do
  # The President is written by hand and is deliberately not scoreable, so the
  # rules below are about everybody else.
  let(:members) do
    path = Rails.root.join("db", "seeds", "data", "united_states", "congress", "congress", "legislators.json")
    JSON.parse(File.read(path)).reject { |m| m["bioguideId"] == LegislatorsCache::POTUS_BIOGUIDE_ID }
  end

  def terms_of(member)
    Array(member.dig("terms", "item"))
  end

  it "gives every member at least one term" do
    without_terms = members.select { |m| terms_of(m).empty? }.pluck("bioguideId")

    expect(without_terms).to be_empty
  end

  it "says when every term started, when it ended, and which state it was served in" do
    incomplete = members.flat_map { |m|
      terms_of(m)
        .reject { |t| t["startYear"].present? && t["endYear"].present? && t["stateCode"].present? }
        .map { |t| "#{m["bioguideId"]}: #{t.inspect}" }
    }

    expect(incomplete).to be_empty
  end

  # The value that cannot be guessed. A member who changes district keeps one
  # row, so without this the seeder writes today's seat onto terms served
  # somewhere else.
  it "names the district of every House term" do
    without_district = members.flat_map { |m|
      terms_of(m)
        .select { |t| t["chamber"] != "Senate" && t["district"].nil? }
        .map { |t| "#{m["bioguideId"]}: #{t.inspect}" }
    }

    expect(without_district).to be_empty
  end

  # legislator_terms is unique on (legislator, term_start_year), and the seeder
  # keeps only the first of any pair sharing a year. Two terms in one year
  # would silently throw one away.
  it "gives no member two terms starting in the same year" do
    repeated = members.filter_map { |m|
      years = terms_of(m).map { |t| t["startYear"] }
      "#{m["bioguideId"]}: #{years.tally.select { |_, n| n > 1 }.keys.inspect}" if years.uniq.size != years.size
    }

    expect(repeated).to be_empty
  end

  # Why congress.gov's own member endpoint was rejected as the source: it
  # reports one entry per Congress, which makes every senate term two years.
  # Sway reads the end year to decide who is in office, so a two-year senate
  # term takes a sitting senator out of office four years early.
  it "keeps every senate term six years long" do
    wrong_length = members.flat_map { |m|
      terms_of(m)
        .select { |t| t["chamber"] == "Senate" }
        .reject { |t| (t["endYear"] - t["startYear"]) == 6 }
        .map { |t| "#{m["bioguideId"]}: #{t["startYear"]}-#{t["endYear"]}" }
    }

    # A senator who resigned or died part way through leaves a shorter term
    # behind, and a seat filled at a special election leaves two. Those are
    # real, so the rule is about the great majority rather than every row.
    senate_terms = members.sum { |m| terms_of(m).count { |t| t["chamber"] == "Senate" } }
    expect(wrong_length.size).to be < (senate_terms * 0.2),
      "#{wrong_length.size} of #{senate_terms} senate terms are not six years:\n  " \
      "#{wrong_length.first(20).join("\n  ")}"
  end

  # The whole point of the file: real history, not one term each.
  it "carries more than the term each member is serving now" do
    with_history = members.count { |m| terms_of(m).size > 1 }

    expect(with_history).to be > (members.size / 2)
  end
end
