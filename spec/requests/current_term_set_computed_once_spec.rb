# frozen_string_literal: true

require "rails_helper"

# @lat: [[current-legislator-term#Why the answer is worked out once per request]]
RSpec.describe "The current-term set is worked out once per request", type: :request do
  include_context "SessionDouble"
  include_context "Setup"
  include ActiveSupport::Testing::TimeHelpers

  def candidate_queries_during
    queries = []
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql].to_s
      queries << sql if sql.match?(/FROM\s+"legislator_terms"/i) && sql.match?(/term_start_year/i)
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscription)
    queries.partition { |sql| sql.match?(/legislator_id/i) }
  end

  def legislator_term_rows_during
    rows = 0
    subscription = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |*, payload|
      instantiated = payload[:record_count].to_i #: Integer
      rows += instantiated if payload[:class_name] == "LegislatorTerm"
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscription)
    rows
  end

  it "evaluates once while rendering a page that shows legislators" do
    setup

    narrowed, whole_set = candidate_queries_during do
      get legislators_path
      expect(response).to have_http_status(:ok)
    end

    expect(whole_set.size).to eq(0)
    expect(narrowed.size).to be >= 1
  end

  it "works the answer out again once a term row is written" do
    _sway_locale, user = setup
    legislator = user.user_legislators.first.legislator
    term_id = legislator.legislator_terms.first.id

    expect(LegislatorTerm.current_ids).to include(term_id)

    legislator.legislator_terms.destroy_all

    expect(LegislatorTerm.current_ids).not_to include(term_id)
  end

  # @lat: [[current-legislator-term#Why the memo is dropped by watching statements, not callbacks]]
  it "works the answer out again after a write that fires no callbacks" do
    _sway_locale, user = setup
    legislator = user.user_legislators.first.legislator
    term = legislator.legislator_terms.first

    expect(LegislatorTerm.current_ids).to include(term.id)

    term.update_columns(ended_on: Date.current - 1.day, ended_on_source: LegislatorTerm::DateSource::OBSERVED)

    expect(LegislatorTerm.current_ids).not_to include(term.id)
    expect(legislator.reload.serving?).to be(false)
  end

  it "works the answer out again after a relation write that fires no callbacks" do
    _sway_locale, user = setup
    legislator = user.user_legislators.first.legislator
    term = legislator.legislator_terms.first

    expect(LegislatorTerm.current_ids).to include(term.id)

    LegislatorTerm.where(id: term.id).delete_all

    expect(LegislatorTerm.current_ids).not_to include(term.id)
  end

  it "works the answer out again once the date has rolled over" do
    setup

    today = LegislatorTerm.current_ids
    expect(today).to be_present

    travel_to(Date.current + 60.years) do
      expect(LegislatorTerm.current_ids).to eq([])
    end

    expect(LegislatorTerm.current_ids).to eq(today)
  end

  # @lat: [[current-legislator-term#Why narrowing by legislator has its own entry point]]
  it "reads only the named legislators' rows when asked for a narrowed answer" do
    sway_locale, user = setup
    legislator = user.user_legislators.first.legislator

    3.times do |index|
      district = create(:district, sway_locale: sway_locale, name: "Stranger District #{index}")
      stranger = create(
        :legislator,
        district: district,
        sway_locale: sway_locale,
        external_id: "stranger-#{index}"
      )
      create(:legislator_term, legislator: stranger, district: district)
    end

    rows = legislator_term_rows_during do
      expect(LegislatorTerm.current_for([legislator.id]).pluck(:legislator_id)).to eq([legislator.id])
    end

    expect(rows).to eq(0)

    instantiated_rows = legislator_term_rows_during do
      terms = LegislatorTerm.current_for([legislator.id]).to_a
      expect(terms.map(&:legislator_id)).to eq([legislator.id])
    end

    expect(instantiated_rows).to eq(legislator.legislator_terms.count)
  end
end
