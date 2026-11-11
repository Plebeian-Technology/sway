# frozen_string_literal: true

require "rails_helper"

RSpec.describe MirroredAssetUrl do
  describe ".for" do
    let(:legislator) { create(:legislator, photo_url: "https://example.com/outside.png") }

    def attach_photo(record)
      record.photo.attach(
        io: StringIO.new("photo"),
        filename: "photo.png",
        content_type: "image/png"
      )
    end

    it "gives our own address when we hold a copy" do
      attach_photo(legislator)

      result = described_class.for(legislator.photo, fallback: legislator.photo_url)

      expect(result).to include("/rails/active_storage/blobs/proxy/")
      expect(result).to start_with("http")
    end

    it "gives the original address when we hold no copy" do
      result = described_class.for(legislator.photo, fallback: legislator.photo_url)

      expect(result).to eql("https://example.com/outside.png")
    end

    it "leaves the address column alone" do
      attach_photo(legislator)

      described_class.for(legislator.photo, fallback: legislator.photo_url)

      expect(legislator.reload.photo_url).to eql("https://example.com/outside.png")
    end

    it "gives the original address when the copy has no stored file behind it" do
      allow(legislator.photo).to receive(:attached?).and_return(true)
      allow(Rails.application.routes.url_helpers)
        .to receive(:rails_storage_proxy_url)
        .and_raise(ArgumentError, "Missing host to link to!")

      result = described_class.for(legislator.photo, fallback: legislator.photo_url)

      expect(result).to eql("https://example.com/outside.png")
    end

    it "returns the fallback for a record with no attachment object at all" do
      expect(described_class.for(nil, fallback: "https://example.com/outside.png"))
        .to eql("https://example.com/outside.png")
    end

    # 34 organizations store a bare bucket file name instead of an address
    # Building the real address is what makes their icons load.
    it "builds an escaped bucket address from a bare file name with a space" do
      bucket = SwayGoogleCloudStorage::BUCKETS[:ASSETS]
      bare_name = "baltimore-maryland-united_states/MCB Real Estate-1718656727447.jpg"

      result = described_class.for(nil, fallback: bare_name)

      expect(result).to eql(
        "https://storage.googleapis.com/#{bucket}/baltimore-maryland-united_states/MCB%20Real%20Estate-1718656727447.jpg"
      )
    end

    it "leaves a site-relative path (leading slash) unchanged" do
      result = described_class.for(nil, fallback: "/images/sway-us-light.png")

      expect(result).to eql("/images/sway-us-light.png")
    end

    it "does not treat protocol-relative // URLs as site-relative paths" do
      bucket = SwayGoogleCloudStorage::BUCKETS[:ASSETS]
      result = described_class.for(nil, fallback: "//attacker.com/evil.png")

      expect(result).not_to eql("//attacker.com/evil.png")
      expect(result).to start_with("https://storage.googleapis.com/#{bucket}/")
    end

    it "leaves an existing http/https address unchanged" do
      result = described_class.for(nil, fallback: "https://example.com/outside.png")

      expect(result).to eql("https://example.com/outside.png")
    end

    it "rejects non-http/https schemes like file: and returns nil" do
      expect(described_class.for(nil, fallback: "file:///etc/passwd")).to be_nil
      expect(described_class.for(nil, fallback: "  file:///etc/passwd")).to be_nil
      expect(described_class.for(nil, fallback: "file:///")).to be_nil
      expect(described_class.for(nil, fallback: "javascript:alert(1)")).to be_nil
    end

    it "leaves a nil or blank fallback unchanged" do
      expect(described_class.for(nil, fallback: nil)).to be_nil
      expect(described_class.for(nil, fallback: "")).to eql("")
    end

    it "escapes a bare bucket file name reached via the rescue path too" do
      bucket = SwayGoogleCloudStorage::BUCKETS[:ASSETS]
      bare_legislator = create(:legislator, photo_url: "baltimore-maryland-united_states/Some Org-123.jpg")
      attach_photo(bare_legislator)
      allow(Rails.application.routes.url_helpers)
        .to receive(:rails_storage_proxy_url)
        .and_raise(ArgumentError, "Missing host to link to!")

      result = described_class.for(bare_legislator.photo, fallback: bare_legislator.photo_url)

      expect(result).to eql(
        "https://storage.googleapis.com/#{bucket}/baltimore-maryland-united_states/Some%20Org-123.jpg"
      )
    end
  end
end
