# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislator-identity-value-design#What production_legislator_identifiers_spec.rb checks]]
RSpec.describe "Production snapshot legislator identifiers", :production_snapshot, type: :model do
  include_context "production snapshot (migrated)"

  let(:baltimore) { SwayLocale.resolve_by_computed_name("baltimore-maryland-united_states") }

  # @lat: [[legislator-identity-value-design#What production_legislator_identifiers_spec.rb checks]]
  it "records one identifier per legislator the roster can name, under that locale's own scheme" do
    by_locale_and_source =
      LegislatorIdentifier
        .group(:sway_locale_id, :source)
        .count
        .transform_keys { |(locale_id, source)| [SwayLocale.find(locale_id).name, source] }

    expect(by_locale_and_source).to eq(
      ["congress-congress-united_states", "bioguide"] => 633,
      ["maryland-maryland-united_states", "openstates"] => 195,
      ["baltimore-maryland-united_states", "seat_and_name"] => 16,
      ["baltimore-maryland-united_states", "curated_person"] => 12,
      ["annapolis-maryland-united_states", "curated_person"] => 2
    )
  end

  it "gives no value to two different people, in any locale" do
    shared =
      LegislatorIdentifier
        .group(:sway_locale_id, :source, :value)
        .having("COUNT(DISTINCT legislator_id) > 1")
        .count

    expect(shared).to be_empty,
      "the same identifier points at more than one person: #{shared.keys.inspect}"
  end

  # The seeder resolves a person through this table, so a legislator the roster
  # still names and no identifier row means a duplicate person on the next boot.
  it "identifies every legislator whose row the roster can still name" do
    unidentified = Legislator.where.missing(:legislator_identifiers).to_a

    # The four left over are the Baltimore members who left in 2024 — Burnett,
    # Costello, Mosby and Stokes. No roster names them, and none should: the
    # 2024 council does not contain them. Their records stay whole.
    expect(unidentified.map(&:external_id).sort).to eq(
      %w[eric-costello-2020 kristefer-burnett-2020 nick-mosby-2020 robert-stokes-2020]
    )
    expect(unidentified.map(&:sway_locale_id).uniq).to eq([baltimore.id])
  end

  # The value under a locale's OWN roster scheme is what external_id holds —
  # that is what makes the column and this table say the same thing, and what
  # lets the seeder fall back to external_id when an identifier row is missing.
  it "holds a roster identifier whose value is the external_id it was built from" do
    roster_sources = [
      LegislatorIdentity::BIOGUIDE,
      LegislatorIdentity::OPENSTATES,
      LegislatorIdentity::SEAT_AND_NAME
    ]

    mismatched =
      LegislatorIdentifier
        .where(source: roster_sources)
        .includes(:legislator)
        .reject { |identifier| identifier.value == identifier.legislator.external_id }
        .map { |identifier| "#{identifier.value} vs #{identifier.legislator.external_id}" }

    expect(mismatched).to be_empty,
      "an identifier and its legislator's external_id disagree:\n  #{mismatched.join("\n  ")}"
  end

  # The other kind is deliberate: a name a person USED to go by, pointing at the
  # row they are now. It is the whole reason identity is a table and not a
  # column — one person, more than one thing a source has called them.
  it "keeps every old name pointing at a person who is still here" do
    aliases = LegislatorIdentifier.where(sway_locale: baltimore, source: LegislatorIdentity::CURATED_PERSON).includes(:legislator)

    expect(aliases.count).to eq(12)
    aliases.each do |old_name|
      expect(old_name.value).to match(/-2020\z/)
      expect(old_name.legislator.external_id).not_to eq(old_name.value)
      expect(old_name.legislator.legislator_terms.count).to eq(2)
    end
  end

  describe "Baltimore, the locale whose roster is keyed by seat" do
    it "pairs every seat row with the name published under it" do
      seat_rows =
        Legislator
          .where(sway_locale_id: baltimore.id)
          .select { |legislator| legislator.external_id.include?(LegislatorIdentity::SEPARATOR) }

      expect(seat_rows.size).to eq(16)
      seat_rows.each do |legislator|
        seat, name_key = legislator.external_id.split(LegislatorIdentity::SEPARATOR, 2)
        expect(seat).to match(/\Abaltimore-(district-\d+|mayor|council-president|comptroller)\z/)
        expect(name_key).to eq(
          LegislatorIdentity.name_key(legislator.first_name, legislator.last_name)
        )
      end
    end

    # The whole point of the change: two people who held one seat are two rows,
    # so a successor can never be written over the previous occupant.
    it "leaves room for a successor on a seat that already has an occupant" do
      sitting = Legislator.find_by!(sway_locale_id: baltimore.id, external_id: "baltimore-district-1|mark-parker")

      successor = Legislator.create!(
        sway_locale_id: baltimore.id,
        external_id: "baltimore-district-1|someone-else",
        first_name: "Someone",
        last_name: "Else",
        party: "D"
      )

      expect(successor.id).not_to eq(sitting.id)
      expect(sitting.reload.last_name).to eq("Parker")
    end
  end

  describe "the locales nobody has declared" do
    it "holds no legislators, which is why the backfill could refuse them" do
      undeclared = SwayLocale.all.reject { |sway_locale| SwayLocale::TermRulesRegistry.declared?(sway_locale.name) }

      expect(undeclared).not_to be_empty, "the snapshot should still carry readers' own city and state locales"
      undeclared.each do |sway_locale|
        expect(Legislator.where(sway_locale_id: sway_locale.id).count).to eq(0)
      end
    end
  end
end
