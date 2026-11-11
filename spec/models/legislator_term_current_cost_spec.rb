# frozen_string_literal: true

require "rails_helper"

# @lat: [[current-legislator-term#Why the candidates are bounded in SQL first]]
RSpec.describe "LegislatorTerm.current reads only terms that could be running today", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  def legislator_term_rows_read
    rows = 0
    subscription = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |*, payload|
      record_count = payload[:record_count].to_i #: Integer
      rows += record_count if payload[:class_name] == "LegislatorTerm"
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscription)
    rows
  end

  let(:congress_locale) do
    create(:sway_locale, city: "congress", state: "congress", country: "United States")
  end
  let(:congress_district) { create(:district, sway_locale: congress_locale) }

  let(:running_start_year) { Date.current.year - 1 }
  let(:running_end_year) { Date.current.year + 1 }

  def serving_legislator(external_id:)
    legislator = create(:legislator, sway_locale: congress_locale, external_id: external_id)
    create(
      :legislator_term,
      legislator: legislator,
      district: congress_district,
      term_start_year: running_start_year,
      term_end_year: running_end_year
    )
    legislator
  end

  def add_terms_that_ended_years_ago(count:, legislator:, from: 0)
    count.times do |index|
      start_year = running_start_year - ((from + index + 1) * 2)
      create(
        :legislator_term,
        legislator: legislator,
        district: congress_district,
        term_start_year: start_year,
        term_end_year: start_year + 2
      )
    end
  end

  it "holds steady as terms that ended years ago are added" do
    legislator = serving_legislator(external_id: "serving-1")

    add_terms_that_ended_years_ago(count: 1, legislator: legislator)
    small = legislator_term_rows_read { LegislatorTerm.current.to_a }
    expect(small).to be_positive, "measured no term rows, so this compares nothing"

    add_terms_that_ended_years_ago(count: 6, legislator: legislator, from: 1)
    large = legislator_term_rows_read { LegislatorTerm.current.to_a }

    expect(large).to eq(small)
  end

  it "still picks the running term for a legislator who has served before" do
    legislator = serving_legislator(external_id: "serving-2")
    add_terms_that_ended_years_ago(count: 3, legislator: legislator)

    current = LegislatorTerm.current.where(legislator_id: legislator.id)

    expect(current.count).to eq(1)
    expect(current.first&.term_start_year).to eq(running_start_year)
  end

  it "leaves out a legislator whose only term has ended" do
    legislator = create(:legislator, sway_locale: congress_locale, external_id: "departed-1")
    add_terms_that_ended_years_ago(count: 2, legislator: legislator)

    expect(LegislatorTerm.current.where(legislator_id: legislator.id)).to be_empty
  end

  # @lat: [[current-legislator-term#Why the candidates are bounded in SQL first]]
  it "answers for the day it is called on, not the day before" do
    legislator = serving_legislator(external_id: "serving-3")
    term_ends_on = TermWindow.convening_date(congress_locale, running_end_year)

    travel_to(term_ends_on - 1.day) do
      expect(LegislatorTerm.current.where(legislator_id: legislator.id).count).to eq(1)
    end

    travel_to(term_ends_on) do
      expect(LegislatorTerm.current.where(legislator_id: legislator.id)).to be_empty
    end
  end
end
