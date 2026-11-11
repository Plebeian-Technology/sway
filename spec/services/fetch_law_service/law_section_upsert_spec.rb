# frozen_string_literal: true

require "rails_helper"

# LawSection keys ('art_N__sec_M') don't name their corpus, so a charter
# and a code section sharing a number collide on the index. The upsert must
# report that collision, not silently overwrite it.
RSpec.describe FetchLawService::LawSectionUpsert do
  it "creates a new LawSection for a fresh (locale, key)" do
    sway_locale = create(:sway_locale)

    row = described_class.call(
      sway_locale: sway_locale, key: "art_1__sec_1", article: "1", section: "1",
      title: "T", body: "body", source_path: "charter/art-I/sec-1"
    )

    expect(row).to be_persisted
    expect(row.key).to eq("art_1__sec_1")
  end

  it "is idempotent for a re-upsert from the SAME corpus (updates in place)" do
    sway_locale = create(:sway_locale)
    described_class.call(
      sway_locale: sway_locale, key: "art_1__sec_1", article: "1", section: "1",
      title: "T", body: "old", source_path: "charter/art-I/sec-1"
    )

    expect {
      row = described_class.call(
        sway_locale: sway_locale, key: "art_1__sec_1", article: "1", section: "1",
        title: "T", body: "new", source_path: "charter/art-I/sec-1"
      )
      expect(row.body).to eq("new")
    }.not_to change(LawSection, :count)
  end

  it "raises on a cross-corpus key collision instead of clobbering" do
    sway_locale = create(:sway_locale)
    described_class.call(
      sway_locale: sway_locale, key: "art_1__sec_1", article: "1", section: "1",
      title: "T", body: "charter body", source_path: "charter/art-I/sec-1"
    )

    expect {
      described_class.call(
        sway_locale: sway_locale, key: "art_1__sec_1", article: "1", section: "1",
        title: "T", body: "code body", source_path: "code/art-01/sec-1"
      )
    }.to raise_error(described_class::LawSectionKeyCollisionError, /collides across corpora/)

    # The original charter row is preserved, not overwritten.
    preserved = LawSection.find_by(sway_locale: sway_locale, key: "art_1__sec_1") #: LawSection
    expect(preserved.body).to eq("charter body")
  end
end
