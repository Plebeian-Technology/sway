# == Schema Information
#
# Table name: legislators
# Database name: primary
#
#  id             :integer          not null, primary key
#  email          :string
#  fax            :string
#  first_name     :string           not null
#  last_name      :string           not null
#  last_seeded_at :datetime
#  link           :string
#  party          :string           not null
#  phone          :string
#  photo_url      :string
#  twitter        :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  external_id    :string           not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_legislators_on_external_id                     (external_id)
#  index_legislators_on_sway_locale_id                  (sway_locale_id)
#  index_legislators_on_sway_locale_id_and_external_id  (sway_locale_id,external_id) UNIQUE
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
require "rails_helper"

RSpec.describe Legislator, type: :model do
  describe "validations" do
    it "is valid with factory defaults" do
      expect(build(:legislator)).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a sway_locale" do
      expect(create(:legislator).sway_locale).to be_a(SwayLocale)
    end

    it "does not auto-create a legislator_district_score on create (default-score creation lives on the term-keyed write path)" do
      legislator = create(:legislator)
      expect(legislator.reload.current_district_score).to be_nil
      expect(LegislatorDistrictScore.count).to eq(0)
    end
  end

  describe "#district" do
    it "resolves through the active term" do
      legislator = create(:legislator)
      term = create(:legislator_term, legislator:)

      expect(legislator.reload.district).to eq(term.district)
    end

    it "returns nil (not a raise) for a legislator with no active term" do
      legislator = create(:legislator)

      expect(legislator.district).to be_nil
    end
  end

  describe "#title" do
    it "delegates to the active term" do
      legislator = create(:legislator)
      create(:legislator_term, legislator:, title: "Rep.")

      expect(legislator.reload.title).to eq("Rep.")
    end

    it "returns nil (not a raise) for a legislator with no active term" do
      legislator = create(:legislator)

      expect(legislator.title).to be_nil
    end
  end

  describe "#serving?" do
    it "is true when the legislator has an active term" do
      legislator = create(:legislator)
      create(:legislator_term, legislator:)

      expect(legislator.reload.serving?).to be(true)
    end

    it "is false when the legislator has no active term" do
      legislator = create(:legislator)

      expect(legislator.serving?).to be(false)
    end
  end

  describe ".with_active_term" do
    def query_count_for(n)
      n.times do
        legislator = create(:legislator)
        create(:legislator_term, legislator:)
      end

      count = 0
      counter = ->(*, **) { count += 1 }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        Legislator.with_active_term.each do |legislator|
          legislator.title
          legislator.district
        end
      end
      count
    end

    it "eager-loads active_term/district so query count stays flat as legislator count grows (no N+1)" do
      small_n_count = query_count_for(2)
      large_n_count = query_count_for(5)

      expect(large_n_count).to eq(small_n_count)
    end

    # @lat: [[current-legislator-term#Which term a legislator is serving now]]
    it "bounds the has_one query in SQL and scopes it directly to the owner" do
      create(:legislator).tap { |l| create(:legislator_term, legislator: l) }

      sql = []
      ActiveSupport::Notifications.subscribed(->(*, payload) { sql << payload[:sql] }, "sql.active_record") do
        Legislator.with_active_term.to_a
      end

      candidate_query = sql.find { |s| s.match?(/FROM\s+"legislator_terms"/i) && s.match?(/term_start_year/i) }

      expect(candidate_query).to be_present
      expect(candidate_query).to match(/legislator_id/i)
    end

    it "preserves flat query count when eager-loading 50 legislators without N+1 regression" do
      count_2 = query_count_for(2)
      count_50 = query_count_for(50)

      expect(count_50).to eq(count_2)
    end

    it "scopes active_term directly to legislator_id in SQL in a single query" do
      legislator = create(:legislator)
      create(:legislator_term, legislator: legislator)

      queries = []
      ActiveSupport::Notifications.subscribed(->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }, "sql.active_record") do
        legislator.active_term
      end

      expect(queries.size).to eq(1)
      expect(queries.first).to match(/FROM\s+"legislator_terms"/i)
      expect(queries.first).to match(/"legislator_terms"\."legislator_id"\s*=\s*/i)
    end
  end

  describe "#full_name" do
    it "joins first_name and last_name with a space" do
      legislator = build(:legislator, first_name: "Ada", last_name: "Lovelace")
      expect(legislator.full_name).to eq("Ada Lovelace")
    end
  end
end
