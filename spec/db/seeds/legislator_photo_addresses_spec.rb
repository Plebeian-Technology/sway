# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislator-seed-photo-address-rules#Disqualifying shapes]]
RSpec.describe "the photo addresses in the committed seed files" do
  # @lat: [[legislator-seed-photo-address-rules#Why query strings are stripped, with one exception]]
  # Kept: the query string is a crop instruction, not a token -- stripping it returns a different image.
  allowed_query_string = "ocd-person/943e92d3-98ad-490f-a93a-16182c624a1f"

  def each_seeded_photo
    return enum_for(:each_seeded_photo) unless block_given?

    Rails.root.glob("db/seeds/data/**/legislators*.json").each do |path|
      records = JSON.parse(File.read(path))
      next unless records.is_a?(Array)

      records.each do |record|
        who = record["externalId"] || record["external_id"] || record["bioguideId"] || record["id"]
        address = record["photoUrl"] || record["photo_url"] || record.dig("depiction", "imageUrl") || record["image"]
        yield(who.to_s, address.to_s, path) if address.present?
      end
    end
  end

  it "never stores an address that carries a signature" do
    signed = each_seeded_photo.select { |_who, address, _path| address.include?("X-Amz-Signature") }

    expect(signed).to be_empty,
      "these addresses expire and will be dead before a reader sees them: #{signed.map(&:first).inspect}"
  end

  it "never stores an address that carries an access token meant to expire" do
    tokened = each_seeded_photo.select { |_who, address, _path| address.include?("itok=") }

    expect(tokened).to be_empty,
      "drop the ?itok= — the file is served without it: #{tokened.map(&:first).inspect}"
  end

  it "keeps a query string only where the picture genuinely depends on it" do
    with_query = each_seeded_photo.select { |_who, address, _path| address.include?("?") }.map(&:first)

    expect(with_query).to eq([allowed_query_string]),
      "a new query string appeared. Fetch the address with and without it and compare the bytes. " \
      "Same picture, strip it. Different picture, add it above and say what it does."
  end

  # @lat: [[legislator-seed-photo-address-rules#Disqualifying shapes]]
  it "never stores one address pasted onto the end of another" do
    doubled = each_seeded_photo.select { |_who, address, _path| address.scan("://").size > 1 }

    expect(doubled).to be_empty,
      "there is a second address inside these, and the result answers 404: #{doubled.map(&:first).inspect}"
  end

  # @lat: [[legislator-seed-photo-address-rules#Disqualifying shapes]]
  it "stores only https addresses, so nothing depends on a redirect" do
    insecure = each_seeded_photo.reject { |_who, address, _path| address.start_with?("https://") }

    expect(insecure).to be_empty,
      "these are http, so fetching them relies on the site rewriting the address: #{insecure.map(&:first).inspect}"
  end
end
