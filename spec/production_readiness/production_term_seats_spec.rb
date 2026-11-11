# frozen_string_literal: true

require "rails_helper"

# @lat: [[production-term-seats-spec-design#What spec/migrations/correct_wrong_seat_congress_terms_spec.rb pins]]
RSpec.describe "Production snapshot: Congress terms filed under the wrong seat", :production_snapshot do
  include_context "production snapshot (raw)"

  # [bioguide, term start year, seat stored today, seat the history proves] —
  # the same four rows the migration names.
  def wrong_seat_rows
    [
      ["H001091", 2021, "IA2", "IA1"],
      ["R000608", 2017, "NV0", "NV3"],
      ["C001114", 2023, "UT0", "UT3"],
      ["S001150", 2023, "CA0", "CA30"]
    ]
  end

  def select_value(sql)
    ActiveRecord::Base.connection.select_value(sql)
  end

  def seats_matching(triples)
    conditions = triples.map { |bioguide, year, seat|
      "(l.external_id = '#{bioguide}' AND lt.term_start_year = #{year} AND d.name = '#{seat}')"
    }.join(" OR ")

    select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM legislators l
      JOIN legislator_terms lt ON lt.legislator_id = l.id
      JOIN districts d ON d.id = lt.district_id
      WHERE #{conditions}
    SQL
  end

  def wrong_seat_count
    seats_matching(wrong_seat_rows.map { |bioguide, year, wrong, _right| [bioguide, year, wrong] })
  end

  def right_seat_count
    seats_matching(wrong_seat_rows.map { |bioguide, year, _wrong, right| [bioguide, year, right] })
  end

  # The counts held by the locale score rows under the four terms, as one
  # comparable string. These rows must come through the repoint untouched.
  def locale_score_counts
    select_value(<<~SQL)
      SELECT COUNT(*) || '|' ||
        COALESCE(SUM(s.count_agreed), 0) || '|' ||
        COALESCE(SUM(s.count_disagreed), 0)
      FROM legislator_locale_scores s
      JOIN legislator_terms lt ON lt.id = s.legislator_term_id
      JOIN legislators l ON l.id = lt.legislator_id
      WHERE l.external_id IN ('H001091', 'R000608', 'C001114', 'S001150')
    SQL
  end

  # The seat the committed roster's history names for every (person, term
  # start year) it answers for. Senate terms carry no district number and take
  # 0, the same rule the seeder's district_name uses.
  def seats_the_history_names
    roster_path = Rails.root.join(
      "db", "seeds", "data", "united_states", "congress", "congress", "legislators.json"
    )
    entries = JSON.parse(roster_path.read) #: Array[Hash[String, untyped]]
    seats = {} #: Hash[[String, Integer], String]

    entries.each do |entry|
      next if entry["termsSource"].blank?

      items = entry.dig("terms", "item")
      next unless items.is_a?(Array)

      items.each do |item|
        state = item["stateCode"]
        next if state.blank? || item["startYear"].blank?

        seats[[entry["bioguideId"], item["startYear"].to_i]] = "#{state}#{item["district"] || 0}"
      end
    end

    seats
  end

  it "repoints the four wrong-seat terms and touches nothing beside them" do
    if ProductionSnapshot.seat_correction_applied?
      skip "seat correction already recorded on this snapshot; " \
        "the standing no-disagreement example below still guards the outcome"
    end

    expect(wrong_seat_count).to eq(4)
    score_counts_before = locale_score_counts

    ProductionSnapshot.migrate!

    expect(wrong_seat_count).to eq(0)
    expect(right_seat_count).to eq(4)
    expect(locale_score_counts).to eq(score_counts_before)
  end

  # @lat: [[production-term-seats-spec-design#The standing invariant]]
  it "leaves no stored Congress term disagreeing with the history's seat" do
    ProductionSnapshot.migrate!

    expected = seats_the_history_names
    stored = ActiveRecord::Base.connection.select_rows(<<~SQL)
      SELECT l.external_id, lt.term_start_year, d.name
      FROM legislators l
      JOIN sway_locales sl ON sl.id = l.sway_locale_id
      JOIN legislator_terms lt ON lt.legislator_id = l.id
      JOIN districts d ON d.id = lt.district_id
      WHERE sl.city = 'congress' AND sl.region_name = 'congress'
    SQL

    disagreements = stored.filter_map { |bioguide, year, seat|
      proven = expected[[bioguide, year.to_i]]
      next if proven.nil? || proven == seat

      "#{bioguide} #{year}: stored #{seat}, history says #{proven}"
    }

    expect(disagreements).to eq([])
  end
end
