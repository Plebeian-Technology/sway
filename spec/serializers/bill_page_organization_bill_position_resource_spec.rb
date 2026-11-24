# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillPageOrganizationBillPositionResource do
  it "sends the source kind and source URL of a sourced position" do
    position = create(:organization_bill_position,
      source_kind: "news_article", source_url: "https://example.com/article")

    hash = described_class.new(position).serializable_hash

    expect(hash.keys).to match_array(
      %w[id bill_id organization support summary summary_ai_unreviewed source_kind source_url]
    )
    expect(hash["source_kind"]).to eq("news_article")
    expect(hash["source_url"]).to eq("https://example.com/article")
  end

  it "sends null source fields for a position with no recorded origin" do
    position = create(:organization_bill_position)

    hash = described_class.new(position).serializable_hash

    expect(hash).to include("source_kind" => nil, "source_url" => nil)
  end
end
