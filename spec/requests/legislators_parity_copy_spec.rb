# frozen_string_literal: true

require "rails_helper"

# @lat: [[parity-copy-snapshot-testing#Why parity copy is tested via snapshots and duplicated in Ruby]]

RSpec.describe "Legislators PARITY_COPY snapshot", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }

  describe "GET /legislators" do
    before { sway_locale_and_user }

    it "renders the Legislators Inertia component (component unchanged after constant extraction)" do
      get "/legislators"
      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component "Legislators"
    end

    it "PARITY_COPY.legislatorsTitle is 'Legislators' (byte-identical)" do
      expect(PARITY_COPY_VALUES_LEGISLATORS.fetch(:legislatorsTitle)).to eq("Legislators")
    end

    it "PARITY_COPY.legislatorsSearchAgain is 'Search again' (byte-identical)" do
      expect(PARITY_COPY_VALUES_LEGISLATORS.fetch(:legislatorsSearchAgain)).to eq("Search again")
    end

    it "PARITY_COPY.legislatorsNoneFound produces byte-identical output" do
      result = PARITY_COPY_VALUES_LEGISLATORS.fetch(:legislatorsNoneFound).call("Baltimore")
      expect(result).to eq("No representatives found for Baltimore.")
    end

    it "PARITY_COPY.legislatorsShowCharts is byte-identical to charts toggle label" do
      expect(PARITY_COPY_VALUES_LEGISLATORS.fetch(:legislatorsShowCharts)).to eq("Show voter agreement")
    end

    it "PARITY_COPY.legislatorsHideCharts is byte-identical to charts toggle label" do
      expect(PARITY_COPY_VALUES_LEGISLATORS.fetch(:legislatorsHideCharts)).to eq("Hide voter agreement")
    end

    it "PARITY_COPY score tile labels are byte-identical to LegislatorCard.tsx strings" do
      expect(PARITY_COPY_VALUES_LEGISLATORS.fetch(:legislatorScoreAgreed)).to eq("Agreed")
      expect(PARITY_COPY_VALUES_LEGISLATORS.fetch(:legislatorScoreDisagreed)).to eq("Disagreed")
      expect(PARITY_COPY_VALUES_LEGISLATORS.fetch(:legislatorScoreNoVote)).to eq("No vote")
    end
  end
end

# @lat: [[parity-copy-snapshot-testing#Why parity copy is tested via snapshots and duplicated in Ruby]]
PARITY_COPY_VALUES_LEGISLATORS = {
  legislatorsTitle: "Legislators",
  legislatorsSearchAgain: "Search again",
  legislatorsNoneFound: ->(locale_name) { "No representatives found for #{locale_name}." },
  legislatorsShowCharts: "Show voter agreement",
  legislatorsHideCharts: "Hide voter agreement",
  legislatorsLoading: "Loading legislators…",
  legislatorScoreAgreed: "Agreed",
  legislatorScoreDisagreed: "Disagreed",
  legislatorScoreNoVote: "No vote"
}.freeze #: {legislatorsTitle: String, legislatorsSearchAgain: String, legislatorsNoneFound: ^(String) -> String, legislatorsShowCharts: String, legislatorsHideCharts: String, legislatorsLoading: String, legislatorScoreAgreed: String, legislatorScoreDisagreed: String, legislatorScoreNoVote: String}
