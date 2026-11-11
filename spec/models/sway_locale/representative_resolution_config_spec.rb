# frozen_string_literal: true

require "rails_helper"

RSpec.describe SwayLocale::DocumentReader, "representative resolution config" do
  it "declares Congress US0 and Maryland/Baltimore MD0 by exact district name" do
    expect(described_class.find("congress-congress-united_states").locale_wide_district_name).to eq("US0")
    expect(described_class.find("maryland-maryland-united_states").locale_wide_district_name).to eq("MD0")
    expect(described_class.find("baltimore-maryland-united_states").locale_wide_district_name).to eq("MD0")
  end

  it "rejects an unknown representative resolution setting" do
    expect {
      described_class.send(
        :validate_representative_resolution,
        {"first_district_number_zero" => true},
        "locale.yml"
      )
    }.to raise_error(SwayLocale::DocumentReader::ValidationError, /Unknown field/)
  end

  it "rejects an empty configured district name" do
    expect {
      described_class.send(
        :validate_representative_resolution,
        {"locale_wide_district_name" => " "},
        "locale.yml"
      )
    }.to raise_error(SwayLocale::DocumentReader::ValidationError, /non-empty string/)
  end
end
