# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legislator Terms Query Stress and Scalability", type: :request do
  include_context "SessionDouble"

  let(:sway_locale) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }
  let(:user) { create(:user) }
  let(:district) { create(:district, sway_locale:, name: "MD1") }

  def capture_sql_queries(&block)
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA" || sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|PRAGMA|SAVEPOINT|RELEASE)\b/i)
      queries << {sql: sql, name: payload[:name]}
    end
    begin
      block.call
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    queries
  end

  def create_legislator_with_terms(term_count:, has_user_scores: true, has_explanations: true, user_override: nil)
    target_user = user_override || user
    leg = create(:legislator, sway_locale:, district:)
    u_leg = create(:user_legislator, user: target_user, legislator: leg)

    (1..term_count).each do |i|
      is_active = (i == term_count)
      start_year = 2025 - ((term_count - i) * 2)
      end_year = start_year + 2

      term = create(
        :legislator_term,
        legislator: leg,
        district:,
        term_start_year: start_year,
        term_end_year: end_year,
        began_on: Date.new(start_year, 1, 3),
        began_on_source: "published",
        ended_on: is_active ? nil : Date.new(end_year, 1, 3),
        ended_on_source: is_active ? nil : "published"
      )

      create(:legislator_district_score, legislator_term: term, count_agreed: 10 + i, count_disagreed: 2 + i)
      create(:legislator_locale_score, legislator_term: term, count_agreed: 20 + i, count_disagreed: 4 + i)

      if has_user_scores
        create(:user_legislator_term_score, user_legislator: u_leg, legislator_term: term, count_agreed: 5, count_disagreed: 1)
      end

      if has_explanations && i.odd?
        create(
          :historical_score_explanation,
          user: target_user,
          legislator: leg,
          score_type: "term_#{term.id}",
          title: "Audit #{i}",
          body: "Adjustment #{i}",
          delta: 0.02
        )
      end
    end

    [leg, u_leg]
  end

  describe "GET /legislators/:id O(1) query count across term counts" do
    it "measures query counts for 1 term, 5 terms, and 10 terms (authenticated)" do
      session_hash[:user_id] = user.id

      leg1, = create_legislator_with_terms(term_count: 1)
      leg5, = create_legislator_with_terms(term_count: 5)
      leg10, = create_legislator_with_terms(term_count: 10)

      get "/legislators/#{leg1.id}"
      expect(response).to have_http_status(:ok)

      queries_1 = capture_sql_queries { get "/legislators/#{leg1.id}" }
      queries_5 = capture_sql_queries { get "/legislators/#{leg5.id}" }
      queries_10 = capture_sql_queries { get "/legislators/#{leg10.id}" }

      puts "\n--- GET /legislators/:id (Authenticated) ---"
      puts "1 term query count: #{queries_1.size}"
      puts "5 terms query count: #{queries_5.size}"
      puts "10 terms query count: #{queries_10.size}"

      expect(queries_1.size).to eq(queries_5.size)
      expect(queries_5.size).to eq(queries_10.size)
    end

    it "executes identical query count for 1 term, 5 terms, and 10 terms (unauthenticated)" do
      session_hash.clear

      leg1, = create_legislator_with_terms(term_count: 1, has_user_scores: false, has_explanations: false)
      leg5, = create_legislator_with_terms(term_count: 5, has_user_scores: false, has_explanations: false)
      leg10, = create_legislator_with_terms(term_count: 10, has_user_scores: false, has_explanations: false)

      queries_1 = capture_sql_queries { get "/legislators/#{leg1.id}" }
      queries_5 = capture_sql_queries { get "/legislators/#{leg5.id}" }
      queries_10 = capture_sql_queries { get "/legislators/#{leg10.id}" }

      puts "\n--- GET /legislators/:id (Unauthenticated) ---"
      puts "1 term query count: #{queries_1.size}"
      puts "5 terms query count: #{queries_5.size}"
      puts "10 terms query count: #{queries_10.size}"

      expect(queries_1.size).to eq(queries_5.size)
      expect(queries_5.size).to eq(queries_10.size)
    end
  end

  describe "GET /legislators roster serialization query scaling across term counts" do
    it "asserts constant query count on GET /legislators when increasing term counts per legislator" do
      user_b = create(:user)
      session_hash.clear
      session_hash[:user_id] = user_b.id
      session_hash[:sway_locale_id] = sway_locale.id

      _leg1, = create_legislator_with_terms(term_count: 2, user_override: user_b)
      _leg2, = create_legislator_with_terms(term_count: 2, user_override: user_b)

      queries_2_terms = capture_sql_queries { get "/legislators", headers: {"Accept" => "application/json"} }
      expect(response).to have_http_status(:ok)

      user_c = create(:user)
      session_hash.clear
      session_hash[:user_id] = user_c.id
      session_hash[:sway_locale_id] = sway_locale.id

      _leg_c1, = create_legislator_with_terms(term_count: 5, user_override: user_c)
      _leg_c2, = create_legislator_with_terms(term_count: 5, user_override: user_c)

      queries_5_terms = capture_sql_queries { get "/legislators", headers: {"Accept" => "application/json"} }
      expect(response).to have_http_status(:ok)

      puts "\n--- GET /legislators (2 terms vs 5 terms per legislator) ---"
      puts "2 terms per legislator query count: #{queries_2_terms.size}"
      puts "5 terms per legislator query count: #{queries_5_terms.size}"

      expect(queries_2_terms.size).to eq(queries_5_terms.size)
    end

    it "measures query scaling on GET /legislators as roster size increases (1 vs 3 vs 5 legislators)" do
      u1 = create(:user, registration_status: "completed", is_registration_complete: true)
      session_hash.clear
      session_hash[:user_id] = u1.id
      session_hash[:sway_locale_id] = sway_locale.id
      create_legislator_with_terms(term_count: 2, user_override: u1)

      q_1_leg = capture_sql_queries { get "/legislators", headers: {"Accept" => "application/json"} }
      expect(response).to have_http_status(:ok)
      matching_term = response.parsed_body["legislators"].first["terms"].find { |t| t["correction_explanation"].present? }
      expect(matching_term).to be_present
      expect(matching_term["correction_explanation"]["title"]).to eq("Audit 1")

      u3 = create(:user, registration_status: "completed", is_registration_complete: true)
      session_hash.clear
      session_hash[:user_id] = u3.id
      session_hash[:sway_locale_id] = sway_locale.id
      3.times { create_legislator_with_terms(term_count: 2, user_override: u3) }
      q_3_leg = capture_sql_queries { get "/legislators", headers: {"Accept" => "application/json"} }
      expect(response).to have_http_status(:ok)

      u5 = create(:user, registration_status: "completed", is_registration_complete: true)
      session_hash.clear
      session_hash[:user_id] = u5.id
      session_hash[:sway_locale_id] = sway_locale.id
      5.times { create_legislator_with_terms(term_count: 2, user_override: u5) }
      q_5_leg = capture_sql_queries { get "/legislators", headers: {"Accept" => "application/json"} }
      expect(response).to have_http_status(:ok)

      puts "\n--- GET /legislators roster scaling (1 vs 3 vs 5 legislators) ---"
      puts "1 legislator query count: #{q_1_leg.size}"
      puts "3 legislators query count: #{q_3_leg.size}"
      puts "5 legislators query count: #{q_5_leg.size}"

      if q_1_leg.size != q_3_leg.size
        puts "Queries for 1 legislator:"
        q_1_leg.each_with_index { |q, idx| puts "  [#{idx + 1}] #{q[:name]}: #{q[:sql]}" }
        puts "Queries for 3 legislators:"
        q_3_leg.each_with_index { |q, idx| puts "  [#{idx + 1}] #{q[:name]}: #{q[:sql]}" }
      end

      expect(q_1_leg.size).to eq(q_3_leg.size)
    end
  end
end
