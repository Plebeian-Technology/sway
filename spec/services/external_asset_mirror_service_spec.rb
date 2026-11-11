require "rails_helper"

RSpec.describe ExternalAssetMirrorService do
  describe ".call" do
    let(:organization) { create(:organization, icon_url: source_url) }
    let(:source_url) { "https://example.com/logo.png" }

    # resolve_final_url GETs and reads only headers, following
    # redirects before anything downloads. This fake answers 200 with no
    # redirect, so the default URL reaches Down.download unchanged.
    before { stub_request(:get, source_url).to_return(status: 200) }

    it "mirrors an external asset and preserves the upstream icon_url" do
      download = Tempfile.new(%w[logo .png])
      download.write("png")
      download.rewind
      download.define_singleton_method(:content_type) { "image/png" }

      # The download has limits now: check that the size cap and the redirect
      # limit are passed along. This fails against the old, unlimited
      # Down.download call.
      allow(Down).to receive(:download)
        .with(source_url, max_size: ExternalAssetMirrorService::MAX_DOWNLOAD_BYTES, max_redirects: 0)
        .and_return(download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:mirrored)
      # url_column keeps pointing at the outside source. The local copy is a
      # fallback for later use, not a replacement for the authoritative URL.
      expect(organization.reload.icon_url).to eql(source_url)
      expect(organization.icon).to be_attached
    end

    it "preserves url_column when source returns 404 — only purges the attachment" do
      organization.icon.attach(
        io: StringIO.new("icon"),
        filename: "icon.png",
        content_type: "image/png"
      )
      allow(Down).to receive(:download).and_raise(
        Down::NotFound.new("not found")
      )

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      # The result name reflects the current behavior. url_column holds the
      # value the seeds set and MUST survive a passing 404 upstream, so a later
      # mirroring run can recover.
      expect(result).to eql(:upstream_not_found)
      expect(organization.reload.icon_url).to eql(source_url)
      expect(organization.icon).not_to be_attached
    end

    it "skips internal sway urls" do
      organization.update!(icon_url: "https://app.sway.vote/images/logo.png")
      allow(Down).to receive(:download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:skipped)
      expect(Down).not_to have_received(:download)
    end

    it "treats our apex and subdomains as internal but not a lookalike host" do
      expect(described_class.send(:internal_asset_url?, "https://sway.vote/x.png")).to be(true)
      expect(described_class.send(:internal_asset_url?, "https://app.sway.vote/x.png")).to be(true)
      expect(described_class.send(:internal_asset_url?, "https://evilsway.vote/x.png")).to be(false)
      expect(described_class.send(:internal_asset_url?, "https://notsway.vote/x.png")).to be(false)
    end

    it "skips internal GCS bucket urls" do
      organization.update!(
        icon_url: "https://storage.googleapis.com/#{SwayGoogleCloudStorage::BUCKETS[:ASSETS]}/logo.png"
      )
      allow(Down).to receive(:download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
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
          url_column: "icon_url"
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
          url_column: "icon_url"
        )

      expect(result).to eql(:skipped)
      expect(Down).not_to have_received(:download)
    end

    it "soft-fails on non-404 errors and preserves original url" do
      allow(Down).to receive(:download).and_raise(
        Down::ConnectionError.new("connection refused")
      )

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:failed_soft)
      expect(organization.reload.icon_url).to eql(source_url)
    end

    it "remains :mirrored when run twice on the same record (idempotent result, attachment replaced)" do
      # The service no longer overwrites url_column with an internal URL, so
      # a second call still sees the outside URL. Repeat copying is held back
      # at the job queue, not here.
      download_one = Tempfile.new(%w[logo .png])
      download_one.write("png-1")
      download_one.rewind
      download_one.define_singleton_method(:content_type) { "image/png" }

      download_two = Tempfile.new(%w[logo .png])
      download_two.write("png-2")
      download_two.rewind
      download_two.define_singleton_method(:content_type) { "image/png" }

      allow(Down).to receive(:download)
        .with(source_url, max_size: ExternalAssetMirrorService::MAX_DOWNLOAD_BYTES, max_redirects: 0)
        .and_return(download_one, download_two)

      first =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )
      expect(first).to eql(:mirrored)
      expect(organization.reload.icon_url).to eql(source_url)

      second =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )
      expect(second).to eql(:mirrored)
      expect(organization.reload.icon_url).to eql(source_url)
    end

    it "rejects a private-address upstream in production without downloading (SSRF guard)" do
      # The guard only runs in production, so the development rewrite of
      # localhost to the "web" container — which points at a private address —
      # keeps working.
      allow(Rails.env).to receive(:production?).and_return(true)
      organization.update!(icon_url: "http://192.168.1.10/logo.png")
      allow(Down).to receive(:download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:skipped)
      expect(Down).not_to have_received(:download)
    end

    it "rejects an unspecified 0.0.0.0 upstream in production without downloading (SSRF guard)" do
      # 0.0.0.0 isn't reported as private?, loopback?, or link_local?, but the
      # OS routes it to the local machine, so it must be blocked too — it used
      # to slip through to Down.download.
      allow(Rails.env).to receive(:production?).and_return(true)
      organization.update!(icon_url: "http://0.0.0.0:2019/config/")
      allow(Down).to receive(:download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:skipped)
      expect(Down).not_to have_received(:download)
    end

    it "rejects a CGNAT / Tailscale 100.64.0.0/10 upstream in production without downloading" do
      allow(Rails.env).to receive(:production?).and_return(true)
      organization.update!(icon_url: "http://100.100.100.100/logo.png")
      allow(Down).to receive(:download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:skipped)
      expect(Down).not_to have_received(:download)
    end

    it "rejects a host that rebinds from a public IP during initial validation to a blocked IP during redirect resolution in production" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Resolv).to receive(:getaddresses).with("example.com").and_return(["93.184.216.34"], ["127.0.0.1"])
      allow(Down).to receive(:download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:skipped)
      expect(Down).not_to have_received(:download)
    end

    it "rejects non-image content types and returns :failed_soft without attaching" do
      download = Tempfile.new(%w[page .html])
      download.write("<html>not an image</html>")
      download.rewind
      download.define_singleton_method(:content_type) { "text/html; charset=utf-8" }

      allow(Down).to receive(:download)
        .with(source_url, max_size: ExternalAssetMirrorService::MAX_DOWNLOAD_BYTES, max_redirects: 0)
        .and_return(download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:failed_soft)
      expect(organization.reload.icon).not_to be_attached
    end

    it "soft-fails and preserves the url when the download exceeds MAX_DOWNLOAD_BYTES" do
      # Down::TooLarge, raised once the size cap is passed, must end in
      # :failed_soft without blanking the authoritative url.
      allow(Down).to receive(:download).and_raise(
        Down::TooLarge.new("file is too large (11MB, max is 10MB)")
      )

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:failed_soft)
      expect(organization.reload.icon_url).to eql(source_url)
    end

    it "rejects a redirect whose target resolves to a private host in production (per-hop SSRF)" do
      # @lat: [[outbound-fetch-safety#Every redirect hop is checked before it is followed]]
      allow(Rails.env).to receive(:production?).and_return(true)
      organization.update!(icon_url: "https://example.com/photo.jpg")
      stub_request(:get, "https://example.com/photo.jpg")
        .to_return(status: 302, headers: {"Location" => "http://192.168.1.50/evil.png"})
      allow(Down).to receive(:download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:skipped)
      expect(Down).not_to have_received(:download)
      expect(a_request(:any, "http://192.168.1.50/evil.png")).not_to have_been_made
    end

    it "follows a redirect to another public host and mirrors the resolved final URL" do
      # A genuine redirect between two public hosts must still work: walking
      # the hops resolves the final URL and hands THAT to Down, with Down's
      # own redirect-following switched off.
      organization.update!(icon_url: "https://example.com/photo.jpg")
      stub_request(:get, "https://example.com/photo.jpg")
        .to_return(status: 302, headers: {"Location" => "https://cdn.example.org/final.jpg"})
      stub_request(:get, "https://cdn.example.org/final.jpg").to_return(status: 200)

      download = Tempfile.new(%w[final .jpg])
      download.write("jpg")
      download.rewind
      download.define_singleton_method(:content_type) { "image/jpeg" }
      allow(Down).to receive(:download)
        .with("https://cdn.example.org/final.jpg", max_size: ExternalAssetMirrorService::MAX_DOWNLOAD_BYTES, max_redirects: 0)
        .and_return(download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:mirrored)
      expect(a_request(:get, "https://cdn.example.org/final.jpg")).to have_been_made
    end

    it "follows a redirect whose Location header carries a raw space" do
      # A real example: mgaleg.maryland.gov sends "jacobs j.jpg" (a literal
      # space) where it should send "jacobs%20j.jpg". Browsers and curl
      # re-encode it and carry on; URI.join alone raises on it and the whole
      # download used to give up with no explanation.
      organization.update!(icon_url: "http://mgaleg.maryland.gov/2016RS/images/jacobs%20j.jpg")
      stub_request(:get, "http://mgaleg.maryland.gov/2016RS/images/jacobs%20j.jpg")
        .to_return(status: 301, headers: {"Location" => "https://mgaleg.maryland.gov/2016RS/images/jacobs j.jpg"})
      stub_request(:get, "https://mgaleg.maryland.gov/2016RS/images/jacobs%20j.jpg").to_return(status: 200)

      download = Tempfile.new(%w[jacobs .jpg])
      download.write("jpg")
      download.rewind
      download.define_singleton_method(:content_type) { "image/jpeg" }
      allow(Down).to receive(:download)
        .with("https://mgaleg.maryland.gov/2016RS/images/jacobs%20j.jpg",
          max_size: ExternalAssetMirrorService::MAX_DOWNLOAD_BYTES, max_redirects: 0)
        .and_return(download)

      result =
        described_class.call(
          record: organization,
          attachment_name: "icon",
          url_column: "icon_url"
        )

      expect(result).to eql(:mirrored)
      expect(a_request(:get, "https://mgaleg.maryland.gov/2016RS/images/jacobs%20j.jpg")).to have_been_made
    end

    it "closes the probe connection inside the request block without draining the response body" do
      http_double = instance_double(Net::HTTP, started?: true)
      response_double = instance_double(Net::HTTPOK)
      allow(response_double).to receive(:is_a?).with(Net::HTTPRedirection).and_return(false)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:start).and_yield(http_double)
      allow(http_double).to receive(:finish)
      allow(http_double).to receive(:request) do |_req, &block|
        block.call(response_double)
        raise "probe did not return early — Net::HTTPResponse#reading_body would drain body"
      end

      expect(described_class.send(:redirect_location_for, source_url)).to be_nil
      expect(http_double).to have_received(:finish)
    end

    # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
    context "the container switch (IS_DOCKER)" do
      let(:localhost_url) { "https://localhost:3000/logo.png" }
      let(:rewritten_url) { "http://web:3000/logo.png" }

      before { organization.update!(icon_url: localhost_url) }

      it "rewrites a localhost source to the container host when the switch is on" do
        stub_request(:get, rewritten_url).to_return(status: 200)
        download = Tempfile.new(%w[logo .png])
        download.write("png")
        download.rewind
        download.define_singleton_method(:content_type) { "image/png" }
        allow(Down).to receive(:download)
          .with(rewritten_url, max_size: ExternalAssetMirrorService::MAX_DOWNLOAD_BYTES, max_redirects: 0)
          .and_return(download)

        with_app_config(:ops, is_docker: true) do
          result =
            described_class.call(
              record: organization,
              attachment_name: "icon",
              url_column: "icon_url"
            )

          expect(result).to eql(:mirrored)
        end
      end

      it "leaves a localhost source unrewritten when the switch is off" do
        stub_request(:get, localhost_url).to_return(status: 200)
        download = Tempfile.new(%w[logo .png])
        download.write("png")
        download.rewind
        download.define_singleton_method(:content_type) { "image/png" }
        allow(Down).to receive(:download)
          .with(localhost_url, max_size: ExternalAssetMirrorService::MAX_DOWNLOAD_BYTES, max_redirects: 0)
          .and_return(download)

        with_app_config(:ops, is_docker: false) do
          result =
            described_class.call(
              record: organization,
              attachment_name: "icon",
              url_column: "icon_url"
            )

          expect(result).to eql(:mirrored)
        end
      end
    end
  end
end
