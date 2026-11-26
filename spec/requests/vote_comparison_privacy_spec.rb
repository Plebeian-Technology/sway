# frozen_string_literal: true

require "rails_helper"

# @lat: [[voter-privacy-threshold#No endpoint sends a count that could identify a voter]]
RSpec.describe "Vote comparison privacy", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  district_row_keys = %w[bill_score_id district comparison_suppressed for_percent against_percent at_large]

  let!(:sway_locale) { setup.first }
  let(:user) { User.last }
  let!(:bill) { create(:bill, sway_locale:, scheduled_release_date_utc: Time.zone.today) }
  let(:json_headers) { {"Accept" => "application/json"} }

  # The reader's own numbered district, so the bills index keeps its row.
  let!(:reader_district) do
    district = create(:district, sway_locale:, name: "#{sway_locale.region_code}4")
    legislator = create(:legislator, district:)
    create(:legislator_term, legislator:, district:)
    create(:user_legislator, user:, legislator:)
    district
  end
  let!(:small_district) { create(:district, sway_locale:, name: "#{sway_locale.region_code}7") }
  let(:at_large_district) { sway_locale.at_large_district }

  def tally(bill_for:, bill_against:, reader:, small:, at_large:)
    score = bill.bill_score
    score.update!(for: bill_for, against: bill_against)
    {reader_district => reader, small_district => small, at_large_district => at_large}.each do |district, (district_for, district_against)|
      create(:bill_score_district, bill_score: score, district:, for: district_for, against: district_against)
    end
  end

  def bill_show_score
    get "/bills/#{bill.id}", headers: json_headers
    response.parsed_body["bill_score"]
  end

  def bill_of_the_month_score
    get "/bill_of_the_month", headers: json_headers
    response.parsed_body["bill_score"]
  end

  def bills_index_score
    get "/bills"
    expect(inertia).to render_component Pages::BILLS
    inertia_load_deferred_props
    inertia.props[:bills].find { |entry| entry["id"] == bill.id }["bill_score"]
  end

  def bill_scores_score
    get "/bill_scores/#{bill.id}"
    response.parsed_body
  end

  def district_rows
    get "/bill_score_districts/#{bill.bill_score.id}", params: {bill_score_district: {bill_score_id: bill.bill_score.id}}
    response.parsed_body
  end

  score_readers = {
    "GET /bills/:id" => :bill_show_score,
    "GET /bills" => :bills_index_score,
    "GET /bill_of_the_month" => :bill_of_the_month_score,
    "GET /bill_scores/:id" => :bill_scores_score
  }

  context "when the bill has nine votes" do
    before { tally(bill_for: 6, bill_against: 3, reader: [6, 3], small: [0, 0], at_large: [6, 3]) }

    score_readers.each do |endpoint, reader|
      it "#{endpoint} sends no percentages and no district row" do
        score = send(reader)

        expect(score).to include("for_percent" => nil, "against_percent" => nil, "comparison_suppressed" => true)
        expect(score["districts"]).to eq([])
      end
    end

    it "GET /bill_score_districts/:id sends no row" do
      expect(district_rows).to eq([])
    end
  end

  count_keys = %w[for against voters_needed pro_count con_count total_votes]

  def keys_in(node)
    case node
    when Hash then node.flat_map { |key, value| [key.to_s] + keys_in(value) }
    when Array then node.flat_map { |value| keys_in(value) }
    else []
    end
  end

  # @lat: [[voter-privacy-threshold#No endpoint sends a count that could identify a voter]]
  context "when the bill has thirty voters" do
    before { tally(bill_for: 18, bill_against: 12, reader: [9, 3], small: [3, 1], at_large: [18, 12]) }

    score_readers.each do |endpoint, reader|
      it "#{endpoint} sends no vote count and no voters-needed number" do
        expect(keys_in(send(reader)) & count_keys).to eq([])
      end
    end

    it "GET /bills/:id sends the web page no vote count and no voters-needed number" do
      get "/bills/#{bill.id}"

      expect(keys_in(inertia.props[:bill_score]) & count_keys).to eq([])
    end

    it "sends a bearer request no vote count and no voters-needed number" do
      api_token = SecureRandom.hex(32)
      ApiKey.create!(bearer: user, token: api_token)

      get "/bills/#{bill.id}", headers: {"Authorization" => "Bearer #{api_token}"}

      expect(keys_in(response.parsed_body["bill_score"]) & count_keys).to eq([])
    end

    it "GET /bill_score_districts/:id sends no vote count and no voters-needed number" do
      expect(keys_in(district_rows) & count_keys).to eq([])
    end

    it "GET /embed/bills/:id sends no vote count and no voters-needed number" do
      get "/embed/bills/#{bill.id}"

      expect(keys_in(inertia.props[:bill]) & count_keys).to eq([])
    end
  end

  context "when the bill has thirty votes" do
    before { tally(bill_for: 18, bill_against: 12, reader: [9, 3], small: [3, 1], at_large: [18, 12]) }

    score_readers.each do |endpoint, reader|
      it "#{endpoint} sends the bill total and only the district with ten voters, as percentages" do
        score = send(reader)

        expect(score).to include("for_percent" => 60, "against_percent" => 40, "comparison_suppressed" => false)
        expect(score["districts"].map { |row| row["district"]["name"] }).to eq([reader_district.name])
        row = score["districts"].first
        expect(row.keys - %w[legislator_names]).to match_array(district_row_keys)
        expect(row).to include(
          "comparison_suppressed" => false, "for_percent" => 80, "against_percent" => 20, "at_large" => false
        )
      end
    end

    it "GET /bill_score_districts/:id sends only the district with ten voters, with no counts" do
      rows = district_rows

      expect(rows.map { |row| row["district"]["name"] }).to eq([reader_district.name])
      expect(rows.first.keys).to match_array(district_row_keys)
    end

    it "names the district's legislators for a bearer request without adding counts" do
      api_token = SecureRandom.hex(32)
      ApiKey.create!(bearer: user, token: api_token)

      get "/bills/#{bill.id}", headers: {"Authorization" => "Bearer #{api_token}"}

      rows = response.parsed_body.dig("bill_score", "districts")
      expect(rows.map { |row| row["district"]["name"] }).to eq([reader_district.name])
      expect(rows.first.keys).to match_array(district_row_keys + %w[legislator_names])
    end

    it "sends the web bill page the same row without legislator names" do
      get "/bills/#{bill.id}"

      expect(inertia).to render_component Pages::BILL
      rows = inertia.props[:bill_score]["districts"]
      expect(rows.map { |row| row["district"]["name"] }).to eq([reader_district.name])
      expect(rows.first.keys).to match_array(district_row_keys)
    end
  end

  # @lat: [[voter-privacy-threshold#Bill totals are sent as rounded percentages]]
  {
    "ten voters, seven For and three Against" => [[7, 3], 70, 30],
    "nineteen voters, thirteen For and six Against" => [[13, 6], 70, 30],
    "forty voters, thirty-nine For and one Against" => [[39, 1], 95, 5]
  }.each do |description, ((split_for, split_against), for_percent, against_percent)|
    context "when the bill has #{description}" do
      before do
        tally(bill_for: split_for, bill_against: split_against, reader: [split_for, split_against], small: [0, 0], at_large: [split_for, split_against])
      end

      score_readers.each do |endpoint, reader|
        it "#{endpoint} sends #{for_percent} and #{against_percent} for the bill and its district" do
          score = send(reader)

          expect(score).to include("for_percent" => for_percent, "against_percent" => against_percent, "comparison_suppressed" => false)
          expect(score["districts"].pluck("for_percent", "against_percent")).to eq([[for_percent, against_percent]])
        end
      end

      it "sends a bearer request the same percentages" do
        api_token = SecureRandom.hex(32)
        ApiKey.create!(bearer: user, token: api_token)

        get "/bills/#{bill.id}", headers: {"Authorization" => "Bearer #{api_token}"}

        score = response.parsed_body["bill_score"]
        expect(score).to include("for_percent" => for_percent, "against_percent" => against_percent)
        expect(score["districts"].pluck("for_percent", "against_percent")).to eq([[for_percent, against_percent]])
      end

      it "sends the web bill page the same percentages" do
        get "/bills/#{bill.id}"

        expect(inertia).to render_component Pages::BILL
        expect(inertia.props[:bill_score]).to include("for_percent" => for_percent, "against_percent" => against_percent)
      end

      it "GET /bill_score_districts/:id sends the district's percentages" do
        expect(district_rows.pluck("for_percent", "against_percent")).to eq([[for_percent, against_percent]])
      end
    end
  end

  context "when the bill has ten voters who all voted For" do
    before { tally(bill_for: 10, bill_against: 0, reader: [10, 0], small: [0, 0], at_large: [10, 0]) }

    score_readers.each do |endpoint, reader|
      it "#{endpoint} withholds the split exactly as it does under ten voters" do
        score = send(reader)

        expect(score).to include("for_percent" => nil, "against_percent" => nil, "comparison_suppressed" => true)
        expect(score["districts"]).to eq([])
      end
    end

    it "GET /bill_score_districts/:id sends no row" do
      expect(district_rows).to eq([])
    end
  end

  context "when a district's ten voters are unanimous inside a bill that is not" do
    before { tally(bill_for: 17, bill_against: 3, reader: [10, 0], small: [0, 0], at_large: [17, 3]) }

    it "sends no row for that district" do
      expect(bill_show_score).to include("for_percent" => 85, "against_percent" => 15)
      expect(bill_show_score["districts"]).to eq([])
    end
  end

  context "when one of eleven voters sits outside the only district with ten voters" do
    before { tally(bill_for: 8, bill_against: 3, reader: [7, 3], small: [1, 0], at_large: [8, 3]) }

    score_readers.each do |endpoint, reader|
      it "#{endpoint} sends the bill total as percentages and no district row" do
        score = send(reader)

        expect(score).to include("for_percent" => 70, "against_percent" => 30, "comparison_suppressed" => false)
        expect(score["districts"]).to eq([])
      end
    end

    it "GET /bill_score_districts/:id sends no row" do
      expect(district_rows).to eq([])
    end

    it "sends a bearer request no district row" do
      api_token = SecureRandom.hex(32)
      ApiKey.create!(bearer: user, token: api_token)

      get "/bills/#{bill.id}", headers: {"Authorization" => "Bearer #{api_token}"}

      expect(response.parsed_body.dig("bill_score", "districts")).to eq([])
    end
  end

  it "shows a district exactly when its tenth voter arrives" do
    tally(bill_for: 18, bill_against: 12, reader: [6, 3], small: [0, 0], at_large: [18, 12])
    expect(bill_show_score["districts"]).to eq([])

    BillScoreDistrict.find_by!(district: reader_district).update!(for: 7)

    expect(bill_show_score["districts"].pluck("for_percent")).to eq([70])
  end
end
