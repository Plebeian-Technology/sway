require "rails_helper"

RSpec.describe ExternalAssetMirrorService do
  describe ".call" do
    let(:organization) { create(:organization, icon_url: source_url) }
    let(:source_url) { "https://example.com/logo.png" }

    it "mirrors an external asset and updates icon_url" do
      download = Tempfile.new(%w[logo .png])
      download.write("png")
      download.rewind
      download.define_singleton_method(:content_type) { "image/png" }

      allow(Down).to receive(:download).with(source_url).and_return(download)
      allow(Rails.application.routes.url_helpers).to receive(
        :rails_storage_proxy_url,
      ).and_return(
        "https://app.sway.vote/rails/active_storage/blobs/proxy/test",
      )

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url",
        )

      expect(result).to eql(:mirrored)
      expect(organization.reload.icon_url).to include(
        "/rails/active_storage/blobs/proxy/",
      )
      expect(organization.icon).to be_attached
    end

    it "clears URL when source returns 404" do
      organization.icon.attach(
        io: StringIO.new("icon"),
        filename: "icon.png",
        content_type: "image/png",
      )
      allow(Down).to receive(:download).and_raise(
        Down::NotFound.new("not found"),
      )

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url",
        )

      expect(result).to eql(:cleared_not_found)
      expect(organization.reload.icon_url).to be_nil
      expect(organization.icon).not_to be_attached
    end

    it "skips internal sway urls" do
      organization.update!(icon_url: "https://app.sway.vote/images/logo.png")
      allow(Down).to receive(:download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url",
        )

      expect(result).to eql(:skipped)
      expect(Down).not_to have_received(:download)
    end

    it "skips internal GCS bucket urls" do
      organization.update!(
        icon_url: "https://storage.googleapis.com/sway-assets/logo.png",
      )
      allow(Down).to receive(:download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url",
        )

      expect(result).to eql(:skipped)
      expect(Down).not_to have_received(:download)
    end

    it "skips blank urls" do
      organization.update!(icon_url: nil)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url",
        )

      expect(result).to eql(:skipped)
    end

    it "skips non-HTTP urls" do
      organization.update!(icon_url: "ftp://example.com/logo.png")
      allow(Down).to receive(:download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url",
        )

      expect(result).to eql(:skipped)
      expect(Down).not_to have_received(:download)
    end

    it "soft-fails on non-404 errors and preserves original url" do
      allow(Down).to receive(:download).and_raise(
        Down::ConnectionError.new("connection refused"),
      )

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url",
        )

      expect(result).to eql(:failed_soft)
      expect(organization.reload.icon_url).to eql(source_url)
    end

    it "is idempotent when run twice on the same record" do
      download = Tempfile.new(%w[logo .png])
      download.write("png")
      download.rewind
      download.define_singleton_method(:content_type) { "image/png" }

      allow(Down).to receive(:download).with(source_url).and_return(download)
      internal_url =
        "https://app.sway.vote/rails/active_storage/blobs/proxy/test"
      allow(Rails.application.routes.url_helpers).to receive(
        :rails_storage_proxy_url,
      ).and_return(internal_url)

      described_class.call(
        record: organization,
        attachment_name: "icon",
        url_column: "icon_url",
      )
      organization.reload

      # Second call should skip because URL is now internal
      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url",
        )
      expect(result).to eql(:skipped)
    end
  end
end
