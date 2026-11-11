# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
RSpec.describe "Bill Creator summary_sources prop", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:admin) { create(:user, :sway_admin) }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator, extracted_text: "Section A. The Mayor shall do X.")
  end

  before { session_hash[:user_id] = admin.id }

  it "ships the ledger on the summary tab, built from what a run reads now" do
    create(:bill_section_reference, bill: bill, key: "art_1__sec_1", title: "One")

    get summary_bill_creator_path(bill)

    expect(response).to have_http_status(:ok)
    expect(inertia).to render_component(Pages::BILL_CREATOR)
    sources = inertia.props.fetch(:summary_sources)
    expect(sources[:read]).to be_nil
    expect(sources[:now][:source_kind]).to eq("extracted")
    expect(sources[:now][:source_chars]).to eq("Section A. The Mayor shall do X.".length)
    expect(sources[:now][:citation_keys_offered]).to eq(1)
    expect(sources[:summary_generated_at]).to be_nil
  end

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  it "ships the recorded run beside the live reading once a run has written one" do
    create(
      :bill_summary_prompt_snapshot,
      bill: bill, built_at: Time.zone.parse("2026-09-01T09:00:00Z"),
      llm_model: "claude-opus-4-6", llm_provider: "claude",
      facts: {"source_kind" => "diff", "source_chars" => 4_748, "diff_sections_modified" => 22}
    )

    get summary_bill_creator_path(bill)

    read = inertia.props.fetch(:summary_sources).fetch(:read)
    expect(read[:built_at]).to eq("2026-09-01T09:00:00Z")
    expect(read[:llm_model]).to eq("claude-opus-4-6")
    expect(read[:source_kind]).to eq("diff")
    expect(read[:source_chars]).to eq(4_748)
    expect(read.keys.map(&:to_s)).to include("news_articles", "newsroom_domains", "diff_sections_not_found")
  end

  it "answers the summary tab's five-second poll, so the dates move when the pipeline does" do
    get summary_bill_creator_path(bill),
      headers: {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version,
        "X-Inertia-Partial-Component" => Pages::BILL_CREATOR,
        "X-Inertia-Partial-Data" => "bill,summary_sources"
      }

    expect(response).to have_http_status(:ok)
    expect(inertia).to render_component(Pages::BILL_CREATOR)
    expect(inertia.props).to include(:summary_sources)
    expect(inertia.props).not_to have_key(:testimony_coverage)
  end

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  describe "the summary_source_documents prop" do
    it "is left out of an ordinary render, because a recorded source text can be very large" do
      get summary_bill_creator_path(bill)

      expect(response).to have_http_status(:ok)
      expect(inertia.props).not_to have_key(:summary_source_documents)
    end

    it "renders the recorded run's own sections when a partial reload asks for it" do
      create(
        :bill_summary_prompt_snapshot,
        bill: bill, built_at: Time.zone.parse("2026-09-01T09:00:00Z"),
        bill_details_text: "## Bill metadata\n\n- External ID: HB1234",
        source_text: "## Bill text (extracted)\n\nSection A.",
        citations_text: nil, news_text: nil
      )

      get summary_bill_creator_path(bill),
        headers: {
          "X-Inertia" => "true",
          "X-Inertia-Version" => InertiaRails.configuration.version,
          "X-Inertia-Partial-Component" => Pages::BILL_CREATOR,
          "X-Inertia-Partial-Data" => "summary_source_documents"
        }

      documents = inertia.props.fetch(:summary_source_documents)
      expect(documents[:origin]).to eq("run")
      expect(documents[:built_at]).to eq("2026-09-01T09:00:00Z")
      expect(documents[:bill_details]).to include("## Bill metadata")
      expect(documents[:source_text]).to include("## Bill text (extracted)")
      expect(documents[:citations]).to be_nil
    end

    it "renders what a run would read now when nothing has been recorded" do
      get summary_bill_creator_path(bill),
        headers: {
          "X-Inertia" => "true",
          "X-Inertia-Version" => InertiaRails.configuration.version,
          "X-Inertia-Partial-Component" => Pages::BILL_CREATOR,
          "X-Inertia-Partial-Data" => "summary_source_documents"
        }

      documents = inertia.props.fetch(:summary_source_documents)
      expect(documents[:origin]).to eq("now")
      expect(documents[:built_at]).to be_nil
      expect(documents[:source_text]).to include("Section A. The Mayor shall do X.")
    end
  end
end
