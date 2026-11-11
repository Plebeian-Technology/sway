# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20261007000001_retire_unavailable_legislator_photo_urls")

RSpec.describe "RetireUnavailableLegislatorPhotoUrls data migration", type: :model do
  let(:migration) { RetireUnavailableLegislatorPhotoUrls.new }
  let(:baltimore) { create(:sway_locale, :baltimore) }
  let(:congress) { create(:sway_locale, :congress) }

  let(:retirements) do
    [
      [baltimore, "kristefer-burnett-2020", "https://www.baltimorecitycouncil.com/sites/default/files/kristerfer_burnett-121_147.png"],
      [baltimore, "eric-costello-2020", "https://www.baltimorecitycouncil.com/sites/default/files/Costello%20Web%20Image.jpg"],
      [baltimore, "robert-stokes-2020", "https://www.baltimorecitycouncil.com/sites/default/files/robert_stokes_jr-121_147.png"],
      [congress, "S001222", "https://raw.githubusercontent.com/unitedstates/images/gh-pages/congress/225x275/S001222.jpg"]
    ]
  end

  it "clears only the four exact locale, identity, and old-address matches" do
    districts = retirements.to_h do |locale, external_id, photo_url|
      district = create(:district, sway_locale: locale)
      legislator = create(:legislator, sway_locale: locale, district:, external_id:, photo_url:)
      [external_id, [legislator, district]]
    end
    preserved = districts.fetch("kristefer-burnett-2020").first
    preserved.photo.attach(
      io: StringIO.new("stored-photo"),
      filename: "stored-photo.png",
      content_type: "image/png"
    )

    wrong_locale = create(
      :legislator,
      sway_locale: baltimore,
      external_id: "S001222",
      photo_url: retirements.last.last
    )
    wrong_identity = create(
      :legislator,
      sway_locale: congress,
      external_id: "unmatched-former-member",
      photo_url: retirements.last.last
    )
    refreshed = districts.fetch("eric-costello-2020").first
    blank_rows = %w[T000489 A000383 G000608].map do |external_id|
      create(:legislator, sway_locale: congress, external_id:, photo_url: nil)
    end
    blank_attributes = blank_rows.map(&:attributes)
    wrong_locale_attributes = wrong_locale.attributes
    wrong_identity_attributes = wrong_identity.attributes
    target_attachment = preserved.photo_attachment
    target_blob_id = preserved.photo.blob.id

    migration.up

    retirements.each do |_locale, external_id, old_url|
      expect(districts.fetch(external_id).first.reload.photo_url).to be_nil,
        "expected #{external_id} to stop exposing #{old_url}"
    end
    expect(wrong_locale.reload.photo_url).to eq(retirements.last.last)
    expect(wrong_identity.reload.photo_url).to eq(retirements.last.last)
    expect(blank_rows.map { |legislator| legislator.reload.photo_url }).to all(be_nil)
    expect(blank_rows.map(&:attributes)).to eq(blank_attributes)
    expect(wrong_locale.reload.attributes).to eq(wrong_locale_attributes)
    expect(wrong_identity.reload.attributes).to eq(wrong_identity_attributes)
    expect(preserved.reload.photo_attachment.id).to eq(target_attachment.id)
    expect(preserved.photo.blob.id).to eq(target_blob_id)
    expect(MirroredAssetUrl.for(preserved.photo, fallback: preserved.photo_url))
      .to match(%r{/rails/active_storage/})

    refreshed.update_columns(photo_url: "https://photos.example.test/refreshed.png")
    migration.up
    expect(refreshed.reload.photo_url).to eq("https://photos.example.test/refreshed.png")
  end

  it "leaves terms, votes, assignments, and score rows unchanged" do
    locale, external_id, photo_url = retirements.first
    district = create(:district, sway_locale: locale)
    legislator = create(:legislator, sway_locale: locale, district:, external_id:, photo_url:)
    term = create(
      :legislator_term,
      legislator:,
      district:,
      term_start_year: 2025,
      term_end_year: 2027,
      began_on: Date.new(2025, 1, 1),
      ended_on: Date.new(2027, 1, 1),
      began_on_source: LegislatorTerm::DateSource::OBSERVED,
      ended_on_source: LegislatorTerm::DateSource::OBSERVED
    )
    user_legislator = create(:user_legislator, legislator:)
    bill = create(:bill, sway_locale: locale)
    vote = create(:legislator_vote, bill:, legislator:, legislator_term: term)
    district_score = create(:legislator_district_score, legislator_term: term, count_agreed: 3)
    locale_score = create(:legislator_locale_score, legislator_term: term, count_disagreed: 2)
    user_score = create(
      :user_legislator_term_score,
      user_legislator:,
      legislator_term: term,
      count_agreed: 1
    )
    before = {
      term: term.attributes,
      vote: vote.attributes,
      assignment: user_legislator.attributes,
      district_score: district_score.attributes,
      locale_score: locale_score.attributes,
      user_score: user_score.attributes
    }

    migration.up

    expect(term.reload.attributes).to eq(before.fetch(:term))
    expect(vote.reload.attributes).to eq(before.fetch(:vote))
    expect(user_legislator.reload.attributes).to eq(before.fetch(:assignment))
    expect(district_score.reload.attributes).to eq(before.fetch(:district_score))
    expect(locale_score.reload.attributes).to eq(before.fetch(:locale_score))
    expect(user_score.reload.attributes).to eq(before.fetch(:user_score))
    expect(legislator.reload.photo_url).to be_nil
  end

  it "is idempotent after the exact old address is cleared" do
    locale, external_id, photo_url = retirements.first
    legislator = create(:legislator, sway_locale: locale, external_id:, photo_url:)

    migration.up
    legislator.reload
    legislator.update_columns(photo_url: "https://photos.example.test/refreshed.png")
    migration.up

    expect(legislator.reload.photo_url).to eq("https://photos.example.test/refreshed.png")
  end
end
