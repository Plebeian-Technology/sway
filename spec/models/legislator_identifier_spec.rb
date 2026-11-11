# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: legislator_identifiers
# Database name: primary
#
#  id             :integer          not null, primary key
#  source         :string           not null
#  value          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  legislator_id  :integer          not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_legislator_identifiers_on_legislator_id                (legislator_id)
#  index_legislator_identifiers_on_locale_and_source_and_value  (sway_locale_id,source,value) UNIQUE
#
# Foreign Keys
#
#  legislator_id   (legislator_id => legislators.id)
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
# The table the seeder resolves a person through.
RSpec.describe LegislatorIdentifier do
  let(:baltimore) do
    create(:sway_locale, city: "baltimore", state: "maryland", country: "United States")
  end
  let(:congress) do
    create(:sway_locale, city: "congress", state: "congress", country: "United States")
  end
  let(:legislator) { create(:legislator, sway_locale: baltimore) }
  let(:identity) do
    LegislatorIdentity.seat_and_name(
      seat: "baltimore-district-1", first_name: "Mark", last_name: "Parker"
    ) #: LegislatorIdentity
  end

  describe ".record! and .legislator_for" do
    it "finds the person a value was recorded against" do
      described_class.record!(legislator: legislator, identity: identity)

      expect(described_class.legislator_for(sway_locale: baltimore, identity: identity)).to eq(legislator)
    end

    it "answers nil for a value nobody has recorded, so the caller makes a new person" do
      expect(described_class.legislator_for(sway_locale: baltimore, identity: identity)).to be_nil
    end

    # db:seed runs on every container boot, so this is called again for every
    # entry every time the app starts.
    it "records the same identity twice without making a second row" do
      described_class.record!(legislator: legislator, identity: identity)

      expect { described_class.record!(legislator: legislator, identity: identity) }
        .not_to change(described_class, :count)
    end

    it "keeps two locales' identical values apart" do
      other_city_legislator = create(:legislator, sway_locale: congress)
      described_class.record!(legislator: legislator, identity: identity)
      described_class.record!(legislator: other_city_legislator, identity: identity)

      expect(described_class.legislator_for(sway_locale: baltimore, identity: identity))
        .to eq(legislator)
      expect(described_class.legislator_for(sway_locale: congress, identity: identity))
        .to eq(other_city_legislator)
    end
  end

  # The many-to-one is the point: one person, more than one thing a source has
  # called them. Zeke Cohen sat for District 1 and is now Council President.
  describe "more than one identifier for one person" do
    it "resolves every recorded value to the same person" do
      as_councilman = LegislatorIdentity.seat_and_name(
        seat: "baltimore-district-1", first_name: "Zeke", last_name: "Cohen"
      ) #: LegislatorIdentity
      as_president = LegislatorIdentity.seat_and_name(
        seat: "baltimore-council-president", first_name: "Zeke", last_name: "Cohen"
      ) #: LegislatorIdentity

      described_class.record!(legislator: legislator, identity: as_councilman)
      described_class.record!(legislator: legislator, identity: as_president)

      expect(described_class.legislator_for(sway_locale: baltimore, identity: as_councilman))
        .to eq(legislator)
      expect(described_class.legislator_for(sway_locale: baltimore, identity: as_president))
        .to eq(legislator)
    end
  end

  describe "validations" do
    it "refuses to give one locale's value to two people" do
      described_class.record!(legislator: legislator, identity: identity)
      someone_else = create(:legislator, sway_locale: baltimore)

      duplicate = described_class.new(
        legislator: someone_else,
        sway_locale_id: baltimore.id,
        source: identity.source,
        value: identity.value
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:value]).to be_present
    end

    it "refuses an identifier filed under a locale the person is not in" do
      wrong_locale = described_class.new(
        legislator: legislator,
        sway_locale_id: congress.id,
        source: identity.source,
        value: identity.value
      )

      expect(wrong_locale).not_to be_valid
      expect(wrong_locale.errors[:sway_locale_id]).to be_present
    end
  end

  describe "#identity" do
    it "reads back as the identity it was recorded from" do
      recorded = described_class.record!(legislator: legislator, identity: identity)

      expect(recorded.identity).to eq(identity)
    end
  end

  it "goes with the person when the person goes" do
    described_class.record!(legislator: legislator, identity: identity)

    expect { legislator.destroy! }.to change(described_class, :count).by(-1)
  end
end
