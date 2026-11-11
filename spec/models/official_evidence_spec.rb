# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: official_evidence
# Database name: primary
#
#  id                 :integer          not null, primary key
#  date_precision     :string
#  date_semantics     :json             not null
#  fact_presence      :string           default("present"), not null
#  fact_type          :string           not null
#  jurisdiction       :string           not null
#  parsed_values      :json             not null
#  payload            :text             not null
#  payload_hash       :string(64)       not null
#  publisher          :string           not null
#  retrieved_at       :datetime         not null
#  source_url         :text             not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  external_record_id :string
#  sway_locale_id     :integer
#
# Indexes
#
#  index_official_evidence_on_hash_and_source             (payload_hash,source_url) UNIQUE
#  index_official_evidence_on_jurisdiction_and_retrieved  (jurisdiction,retrieved_at)
#  index_official_evidence_on_record_and_jurisdiction     (external_record_id,jurisdiction)
#  index_official_evidence_on_sway_locale_id              (sway_locale_id)
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
RSpec.describe OfficialEvidence do
  let(:attributes) do
    {
      publisher: "records.example.gov",
      jurisdiction: "example_executive",
      source_url: "https://records.example.gov/service",
      retrieved_at: Time.current,
      payload: '{"id":"example-person-001"}',
      payload_hash: Digest::SHA256.hexdigest('{"id":"example-person-001"}'),
      fact_type: "executive_service",
      fact_presence: "present",
      date_precision: "exact",
      parsed_values: {"person_identity_source" => "us_executive"},
      date_semantics: {"start" => "inclusive", "end" => "exclusive"}
    }
  end

  # @lat: [[lat.md/reference/official-service-evidence-tests#Official service evidence tests#Immutable evidence keeps its payload digest]]
  it "rejects mutation after evidence is persisted" do
    evidence = described_class.create!(attributes)

    expect { evidence.update!(publisher: "other.example.gov") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { evidence.update_columns(publisher: "other.example.gov") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { evidence.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "rejects a payload hash that does not match the retained source payload" do
    evidence = described_class.new(attributes.merge(payload_hash: "0" * 64))

    expect(evidence).not_to be_valid
    expect(evidence.errors[:payload_hash]).to include("payload_hash does not match payload SHA-256 digest")
  end
end
