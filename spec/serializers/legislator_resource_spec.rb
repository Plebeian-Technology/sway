# frozen_string_literal: true

require "rails_helper"

# The key is still called photo_url, so no screen and no phone app
# had to change. What moved is the address behind it.
RSpec.describe LegislatorResource do
  let(:legislator) { create(:legislator, photo_url: "https://example.com/outside.png") }

  def attach_photo(record)
    record.photo.attach(
      io: StringIO.new("photo"),
      filename: "photo.png",
      content_type: "image/png"
    )
  end

  it "sends our own copy of the portrait when we hold one" do
    attach_photo(legislator)

    hash = described_class.new(legislator).serializable_hash

    expect(hash["photo_url"]).to include("/rails/active_storage/blobs/proxy/")
  end

  it "sends the original address when we hold no copy" do
    hash = described_class.new(legislator).serializable_hash

    expect(hash["photo_url"]).to eql("https://example.com/outside.png")
  end

  it "never writes our address into the database" do
    attach_photo(legislator)

    described_class.new(legislator).serializable_hash

    expect(legislator.reload.photo_url).to eql("https://example.com/outside.png")
  end

  describe "the term a payload describes" do
    it "sends the district of a legislator whose only term has ended" do
      district = create(:district, name: "D-9")
      former = create(:legislator, district: district)
      create(:legislator_term, legislator: former, district: district,
        term_start_year: 2015, term_end_year: 2019, title: "Rep.")

      hash = described_class.new(former).serializable_hash

      expect(former.active_term).to be_nil
      expect(hash["active"]).to be(false)
      expect(hash["district"]).to include("id" => district.id, "name" => "D-9")
      expect(hash["title"]).to eql("Rep.")
      expect(hash["term_end_year"]).to eql(2019)
    end

    it "sends the running term's district for a legislator still in office" do
      district = create(:district, name: "D-1")
      serving = create(:legislator, district: district)
      create(:legislator_term, legislator: serving, district: district)

      hash = described_class.new(serving).serializable_hash

      expect(hash["active"]).to be(true)
      expect(hash["district"]).to include("id" => district.id, "name" => "D-1")
    end

    it "sends no district for a legislator who never held a term" do
      never_seated = create(:legislator)

      hash = described_class.new(never_seated).serializable_hash

      expect(hash["district"]).to be_nil
    end
  end

  # alba hands back string keys here, which is why every assertion above reads
  # one. The controllers merge symbol keys onto this hash and render it as
  # JSON, where the difference disappears.
  it "still sends photo_url, so the payload shape is unchanged" do
    expect(described_class.new(legislator).serializable_hash).to have_key("photo_url")
  end

  describe ".terms_for" do
    let(:sway_locale) { create(:sway_locale, city: "congress", state: "congress", country: "United States") }
    let(:district) { create(:district, sway_locale:, name: "MD1") }
    let(:user) { create(:user) }
    let(:term_2023) { create(:legislator_term, :prior_term, legislator:, district:, term_start_year: 2023, term_end_year: 2025) }
    let(:term_2025) { create(:legislator_term, legislator:, district:, term_start_year: 2025, term_end_year: 2027, ended_on: nil) }

    it "returns an empty array when a legislator has zero terms" do
      expect(described_class.terms_for(create(:legislator, sway_locale:, district:))).to eq([])
    end

    it "attaches term-specific, lifetime, and hash-indexed historical_score_explanations while ignoring other legislators' explanations" do
      term_2023
      term_2025
      other_leg = create(:legislator, sway_locale:, district:)

      exp_2023 = create(:historical_score_explanation, user:, legislator:, score_type: "term_#{term_2023.id}", title: "2023 Audit", body: "Weights", delta: -0.05)
      exp_lifetime = create(:historical_score_explanation, user:, legislator:, score_type: "lifetime", title: "Lifetime", body: "General", delta: 0.12)
      exp_other = create(:historical_score_explanation, user:, legislator: other_leg, score_type: "term_#{term_2023.id}", title: "Other", body: "Other", delta: 0.5)

      res_array = described_class.terms_for(legislator, {historical_score_explanations: [exp_2023, exp_lifetime, exp_other]})
      p_2025 = res_array.find { |t| t[:id] == term_2025.id } || {}
      p_2023 = res_array.find { |t| t[:id] == term_2023.id } || {}

      expect(p_2025[:correction_explanation]).to include(title: "Lifetime", score_type: "lifetime")
      expect(p_2023[:correction_explanation]).to include(title: "2023 Audit", score_type: "term_#{term_2023.id}")

      res_hash = described_class.terms_for(legislator, {historical_score_explanations: {term_2023.id => exp_2023}})
      p_hash_2023 = res_hash.find { |t| t[:id] == term_2023.id } || {}
      expect(p_hash_2023[:correction_explanation]).to include(title: "2023 Audit")
    end
  end
end
