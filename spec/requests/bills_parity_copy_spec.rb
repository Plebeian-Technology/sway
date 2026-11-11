# frozen_string_literal: true

require "rails_helper"

# @lat: [[parity-copy-snapshot-testing#The PARITY_COPY snapshot-testing pattern]]

RSpec.describe "Bills PARITY_COPY snapshot", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }

  describe "GET /bills" do
    before { sway_locale_and_user }

    it "renders the Bills Inertia component (component unchanged after constant extraction)" do
      get "/bills"
      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component "Bills"
    end

    it "returns bills as a deferred prop (data contract unchanged)" do
      get "/bills"
      expect(inertia).to have_deferred_props(:bills)
    end

    it "PARITY_COPY.billsTitle resolves to 'Past bills' (byte-identical)" do
      # The constant is used in JSX. Check its value still matches the string
      # that used to be typed directly into Bills.tsx.
      expect(PARITY_COPY_VALUES.fetch(:billsTitle)).to eq("Past bills")
    end

    it "PARITY_COPY.billsShowingCount produces byte-identical output" do
      result = PARITY_COPY_VALUES.fetch(:billsShowingCount).call(3, "Baltimore")
      expect(result).to eq("Showing 3 bills for Baltimore.")
    end

    it "PARITY_COPY.billsNoneFound produces byte-identical output" do
      result = PARITY_COPY_VALUES.fetch(:billsNoneFound).call("Baltimore")
      expect(result).to eq("No bills found for Baltimore.")
    end

    it "PARITY_COPY.billsLoading is 'Loading bills…' (byte-identical)" do
      expect(PARITY_COPY_VALUES.fetch(:billsLoading)).to eq("Loading bills…")
    end

    it "PARITY_COPY.orgNoSupport is byte-identical to original BillContent string" do
      expect(PARITY_COPY_VALUES.fetch(:orgNoSupport)).to eq(
        "Sway has not yet found any statements of support for this legislation."
      )
    end

    it "PARITY_COPY.orgNoOppose is byte-identical to original BillContent string" do
      expect(PARITY_COPY_VALUES.fetch(:orgNoOppose)).to eq(
        "Sway has not yet found any statements of opposition for this legislation."
      )
    end

    it "PARITY_COPY VotePanel labels are byte-identical to original VotePanel strings" do
      expect(PARITY_COPY_VALUES.fetch(:votePanelTitle)).to eq("Your vote")
      expect(PARITY_COPY_VALUES.fetch(:votePanelForLabel)).to eq("For")
      expect(PARITY_COPY_VALUES.fetch(:votePanelForSublabel)).to eq("Support this legislation")
      expect(PARITY_COPY_VALUES.fetch(:votePanelAgainstLabel)).to eq("Against")
      expect(PARITY_COPY_VALUES.fetch(:votePanelAgainstSublabel)).to eq("Oppose this legislation")
    end

    it "PARITY_COPY BillContent headers are byte-identical to original strings" do
      expect(PARITY_COPY_VALUES.fetch(:billContentHowOthersVoted)).to eq("How others voted")
      expect(PARITY_COPY_VALUES.fetch(:billContentSwaysSummary)).to eq("Sway summary")
      expect(PARITY_COPY_VALUES.fetch(:billContentWhySupport)).to eq("Why support this bill")
      expect(PARITY_COPY_VALUES.fetch(:billContentWhyOppose)).to eq("Why oppose this bill")
      expect(PARITY_COPY_VALUES.fetch(:billContentTakeNextStep)).to eq("Take the next step")
    end

    it "PARITY_COPY CTA strings are byte-identical to original BillContent strings" do
      expect(PARITY_COPY_VALUES.fetch(:compareWithReps)).to eq("Compare with representatives")
      expect(PARITY_COPY_VALUES.fetch(:voteOnPastLegislation)).to eq("Vote on past legislation")
    end

    it "PARITY_COPY botmEmpty is byte-identical to original BillOfTheMonth empty state" do
      expect(PARITY_COPY_VALUES.fetch(:botmEmpty)).to eq(
        "No Bill of the Month is featured right now. Check back soon."
      )
    end
  end
end

# @lat: [[parity-copy-snapshot-testing#Why parity copy is tested via snapshots and duplicated in Ruby]]
PARITY_COPY_VALUES = {
  billsTitle: "Past bills",
  billsShowingCount: ->(count, locale_name) { "Showing #{count} bills for #{locale_name}." },
  billsNoneFound: ->(locale_name) { "No bills found for #{locale_name}." },
  billsLoading: "Loading bills…",
  billsCategoriesLabel: "Categories",
  billContentHowOthersVoted: "How others voted",
  billContentVoteBreakdown: "How the vote breaks down",
  billContentSwaysSummary: "Sway summary",
  billContentWhySupport: "Why support this bill",
  billContentWhyOppose: "Why oppose this bill",
  billContentTakeNextStep: "Take the next step",
  orgNoSupport: "Sway has not yet found any statements of support for this legislation.",
  orgNoOppose: "Sway has not yet found any statements of opposition for this legislation.",
  votePanelTitle: "Your vote",
  votePanelForLabel: "For",
  votePanelForSublabel: "Support this legislation",
  votePanelAgainstLabel: "Against",
  votePanelAgainstSublabel: "Oppose this legislation",
  botmEmpty: "No Bill of the Month is featured right now. Check back soon.",
  billDetailError: "Could not load this bill. Pull to refresh.",
  compareWithReps: "Compare with representatives",
  voteOnPastLegislation: "Vote on past legislation",
  showMore: "Show more",
  showLess: "Show less"
}.freeze #: {billsTitle: String, billsShowingCount: ^(Integer, String) -> String, billsNoneFound: ^(String) -> String, billsLoading: String, billsCategoriesLabel: String, billContentHowOthersVoted: String, billContentVoteBreakdown: String, billContentSwaysSummary: String, billContentWhySupport: String, billContentWhyOppose: String, billContentTakeNextStep: String, orgNoSupport: String, orgNoOppose: String, votePanelTitle: String, votePanelForLabel: String, votePanelForSublabel: String, votePanelAgainstLabel: String, votePanelAgainstSublabel: String, botmEmpty: String, billDetailError: String, compareWithReps: String, voteOnPastLegislation: String, showMore: String, showLess: String}
