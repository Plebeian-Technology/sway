# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislator-history-serialization#Why database reads are bounded during history serialization]]
RSpec.describe LegislatorHistoryResource do
  it "executes a bounded and constant number of SELECT queries regardless of representative or score count" do
    count_queries = lambda do |&block|
      queries = [] #: Array[String]
      counter = ->(_name, _start, _finish, _id, payload) {
        sql = payload[:sql].to_s
        queries << sql if payload[:name] != "SCHEMA" && sql.match?(/\A\s*SELECT/i)
      }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      queries
    end

    create_inactive_rep = lambda do |user:, sway_locale:, start_year:, score_count: 2|
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:, sway_locale:)
      term = create(:legislator_term, legislator:, district:,
        term_start_year: start_year, term_end_year: start_year + 4,
        began_on: Date.new(start_year, 1, 1), began_on_source: LegislatorTerm::DateSource::PUBLISHED,
        ended_on: Date.new(start_year + 4, 1, 1), ended_on_source: LegislatorTerm::DateSource::PUBLISHED)

      user_leg = create(:user_legislator, user:, legislator:, active: false)

      if score_count > 0
        create(:user_legislator_term_score, user_legislator: user_leg, legislator_term: term,
          count_agreed: 5, count_disagreed: 2, count_legislator_abstained: 1, count_no_legislator_vote: 0)

        if score_count > 1
          earlier_term = create(:legislator_term, legislator:, district:,
            term_start_year: start_year - 4, term_end_year: start_year,
            began_on: Date.new(start_year - 4, 1, 1), began_on_source: LegislatorTerm::DateSource::PUBLISHED,
            ended_on: Date.new(start_year, 1, 1), ended_on_source: LegislatorTerm::DateSource::PUBLISHED)
          create(:user_legislator_term_score, user_legislator: user_leg, legislator_term: earlier_term,
            count_agreed: 3, count_disagreed: 1, count_legislator_abstained: 0, count_no_legislator_vote: 0)
        end
      end

      user_leg
    end

    sway_locale = create(:sway_locale, :baltimore)

    user1 = create(:user)
    active_district1 = create(:district, sway_locale:)
    create(:user_district, user: user1, district: active_district1, active: true)
    create_inactive_rep.call(user: user1, sway_locale:, start_year: 2016, score_count: 2)
    create_inactive_rep.call(user: user1, sway_locale:, start_year: 2012, score_count: 0)

    user5 = create(:user)
    active_district5 = create(:district, sway_locale:)
    create(:user_district, user: user5, district: active_district5, active: true)
    5.times do |i|
      create_inactive_rep.call(user: user5, sway_locale:, start_year: 2016 - (i * 4), score_count: 2)
    end
    create_inactive_rep.call(user: user5, sway_locale:, start_year: 1992, score_count: 0)

    hash1 = {} #: Hash[String, untyped]
    queries1 = count_queries.call do
      ActiveRecord::Base.uncached do
        hash1 = LegislatorHistoryResource.new(user1, params: {sway_locale:}).serializable_hash
      end
    end

    hash5 = {} #: Hash[String, untyped]
    queries5 = count_queries.call do
      ActiveRecord::Base.uncached do
        hash5 = LegislatorHistoryResource.new(user5, params: {sway_locale:}).serializable_hash
      end
    end

    expect(hash1["sessions"]).to eq(hash1["legislative_sessions"])
    expect(hash5["sessions"]).to eq(hash5["legislative_sessions"])

    entries1 = hash1["sessions"].flat_map { |s| s[:entries] || s["entries"] }
    expect(entries1.size).to eq(2)
    expect(entries1.first).to include(:legislator, :term, :score, :ended_reason)

    entries5 = hash5["sessions"].flat_map { |s| s[:entries] || s["entries"] }
    expect(entries5.size).to eq(6)
    expect(entries5.first).to include(:legislator, :term, :score, :ended_reason)

    expect(queries1.size).to be <= 15
    expect(queries5.size).to be <= 15
    expect(queries5.size).to eq(queries1.size)
  end

  it "preserves identical keys and values for sessions and legislative_sessions" do
    sway_locale = create(:sway_locale, :baltimore)
    user = create(:user)
    active_district = create(:district, sway_locale:)
    create(:user_district, user:, district: active_district, active: true)

    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:, sway_locale:)
    term = create(:legislator_term, legislator:, district:,
      term_start_year: 2020, term_end_year: 2024,
      began_on: Date.new(2020, 1, 1), began_on_source: LegislatorTerm::DateSource::PUBLISHED,
      ended_on: Date.new(2024, 1, 1), ended_on_source: LegislatorTerm::DateSource::PUBLISHED)
    user_leg = create(:user_legislator, user:, legislator:, active: false)
    create(:user_legislator_term_score, user_legislator: user_leg, legislator_term: term,
      count_agreed: 5, count_disagreed: 2, count_legislator_abstained: 1, count_no_legislator_vote: 0)

    hash = {} #: Hash[String, untyped]
    ActiveRecord::Base.uncached do
      hash = LegislatorHistoryResource.new(user, params: {sway_locale:}).serializable_hash
    end

    expect(hash.keys).to match_array(%w[sessions legislative_sessions])
    expect(hash["sessions"]).to eq(hash["legislative_sessions"])
    expect(hash["sessions"]).not_to be_empty
  end

  it "does not reuse one user's history for another collection member" do
    locale = create(:sway_locale)
    users = 2.times.map do
      user = create(:user)
      district = create(:district, sway_locale: locale)
      legislator = create(:legislator, district: district)
      term = create(:legislator_term, :prior_term, legislator: legislator, district: district)
      link = create(:user_legislator, user: user, legislator: legislator, active: false)
      create(:user_legislator_term_score, user_legislator: link, legislator_term: term, count_agreed: user.id)
      user
    end
    expected = users.map { |user| LegislatorHistoryResource.new(user, params: {sway_locale: locale}).serializable_hash }
    actual = LegislatorHistoryResource.new(users, params: {sway_locale: locale}).serializable_hash
    expect(actual).to eq(expected)
  end

  it "serializes empty history users before and after nonempty users without cross-contamination" do
    locale = create(:sway_locale, :baltimore)
    user_empty_1 = create(:user)

    user_nonempty = create(:user)
    district = create(:district, sway_locale: locale)
    legislator = create(:legislator, district: district, sway_locale: locale)
    term = create(:legislator_term, legislator: legislator, district: district,
      term_start_year: 2020, term_end_year: 2024,
      began_on: Date.new(2020, 1, 1), began_on_source: LegislatorTerm::DateSource::PUBLISHED,
      ended_on: Date.new(2024, 1, 1), ended_on_source: LegislatorTerm::DateSource::PUBLISHED)
    user_leg = create(:user_legislator, user: user_nonempty, legislator: legislator, active: false)
    create(:user_legislator_term_score, user_legislator: user_leg, legislator_term: term,
      count_agreed: 5, count_disagreed: 2, count_legislator_abstained: 1, count_no_legislator_vote: 0)

    user_empty_2 = create(:user)

    users = [user_empty_1, user_nonempty, user_empty_2]
    expected = users.map { |u| LegislatorHistoryResource.new(u, params: {sway_locale: locale}).serializable_hash }
    actual = LegislatorHistoryResource.new(users, params: {sway_locale: locale}).serializable_hash #: Array[Hash[String, untyped]]

    expect(actual).to eq(expected)
    expect(actual[0]["sessions"]).to eq([])
    expect(actual[1]["sessions"]).not_to be_empty
    expect(actual[2]["sessions"]).to eq([])
  end
end
