require "rails_helper"

RSpec.describe "WellKnown", type: :request do
  mobile = {
    apple_team_id: "ABCDE12345",
    apple_bundle_id: "app.example.test",
    app_association_hosts: "example.test, app.example.test"
  }.freeze

  around do |example|
    with_app_config(:mobile, **mobile) do
      with_app_config(:webauthn, related_hosts: "example.test, app.example.test") { example.run }
    end
  end

  describe "GET /.well-known/webauthn" do
    it "returns the related origins for app.example.test" do
      host! "app.example.test"

      get "/.well-known/webauthn"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        {"origins" => ["https://example.test", "https://app.example.test"]}
      )
    end

    it "returns the related origins for the bare domain" do
      host! "example.test"

      get "/.well-known/webauthn"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        {"origins" => ["https://example.test", "https://app.example.test"]}
      )
    end

    it "returns an empty response from every host when no related host is configured" do
      with_app_config(:webauthn, related_hosts: "") do
        host! "app.example.test"
        get "/.well-known/webauthn"
      end

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
    end

    it "returns an empty response for non-app hosts" do
      host! "evil.example.com"

      get "/.well-known/webauthn"

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
    end
  end

  describe "/.well-known association files" do
    shared_examples "serves AASA" do |host|
      it "returns application/json from #{host}" do
        host! host
        get "/.well-known/apple-app-site-association"
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
        expect(response.headers["Cache-Control"]).to include("max-age=3600")
        body = JSON.parse(response.body)
        expect(body.dig("webcredentials", "apps")).to eq(["ABCDE12345.app.example.test"])
        expect(body.dig("applinks", "details", 0, "appID")).to eq("ABCDE12345.app.example.test")
        expect(body.dig("applinks", "details", 0, "paths")).to include(
          "/bills/*",
          "/legislators/*",
          "/bill_of_the_week",
          "/bill_of_the_month",
          "/organizations/*/memberships/*",
          "/s/*",
          "/invite/*/*",
          "/invites/*/*",
          "/bill_shares/*"
        )
      end
    end

    # @lat: [[well-known-controller-notes#Why the AASA paths list is tested against the real route table]]
    it "advertises exactly the paths the mobile app claims" do
      host! "example.test"
      get "/.well-known/apple-app-site-association"

      served = JSON.parse(response.body).dig("applinks", "details", 0, "paths")
      source = Rails.root.join("mobile", "src", "navigation", "deepLinkPatterns.ts")
      declared = source.read[/DEEP_LINK_PATTERNS\s*=\s*\[(.*?)\]/m, 1].to_s.scan(/"([^"]+)"/).flatten

      # An empty list would make this pass while comparing nothing, which reads
      # exactly like agreement.
      expect(declared).not_to be_empty
      expect(served).to match_array(declared | ["/bill_of_the_month"])
    end

    it "advertises only paths that are real Sway routes" do
      host! "example.test"
      get "/.well-known/apple-app-site-association"

      paths = JSON.parse(response.body).dig("applinks", "details", 0, "paths")
      expect(paths).to be_present

      redirect_only_paths = ["/bill_of_the_week"]

      unroutable = (paths - redirect_only_paths).reject do |pattern|
        # A '*' stands for whatever a real link carries in that position; an id
        # is the only shape any of these patterns takes.
        Rails.application.routes.recognize_path(pattern.tr("*", "1"), method: :get)
        true
      rescue ActionController::RoutingError
        false
      end

      expect(unroutable).to be_empty
    end

    shared_examples "serves assetlinks" do |host|
      it "returns android asset links from #{host}" do
        host! host
        get "/.well-known/assetlinks.json"
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
        expect(response.headers["Cache-Control"]).to include("max-age=3600")
        body = JSON.parse(response.body)
        expect(body.first.dig("target", "package_name")).to eq("app.example.test")
        expect(body.first.dig("target", "namespace")).to eq("android_app")
        expect(body.first["relation"]).to include(
          "delegate_permission/common.handle_all_urls",
          "delegate_permission/common.get_login_creds"
        )
      end
    end

    include_examples "serves AASA", "example.test"             # bare domain
    include_examples "serves AASA", "app.example.test"
    include_examples "serves assetlinks", "example.test"       # bare domain
    include_examples "serves assetlinks", "app.example.test"

    it "returns 204 for both association files from every host when no association host is configured" do
      with_app_config(:mobile, **mobile, app_association_hosts: "") do
        host! "app.example.test"
        get "/.well-known/apple-app-site-association"
        expect(response).to have_http_status(:no_content)

        get "/.well-known/assetlinks.json"
        expect(response).to have_http_status(:no_content)
      end
    end

    it "returns 204 from unknown host for AASA" do
      host! "random-attacker.example.com"
      get "/.well-known/apple-app-site-association"
      expect(response).to have_http_status(:no_content)
    end

    it "returns 204 for AASA when the Apple team id is unset" do
      with_app_config(:mobile, **mobile, apple_team_id: nil) do
        host! "app.example.test"
        get "/.well-known/apple-app-site-association"
      end

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
    end

    it "returns 204 for AASA when the Apple bundle id is unset" do
      with_app_config(:mobile, **mobile, apple_bundle_id: nil) do
        host! "app.example.test"
        get "/.well-known/apple-app-site-association"
      end

      expect(response).to have_http_status(:no_content)
    end

    it "returns 204 for assetlinks when the bundle id is unset" do
      with_app_config(:mobile, **mobile, apple_bundle_id: nil) do
        host! "app.example.test"
        get "/.well-known/assetlinks.json"
      end

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
    end

    it "returns 204 from unknown host for assetlinks" do
      host! "random-attacker.example.com"
      get "/.well-known/assetlinks.json"
      expect(response).to have_http_status(:no_content)
    end

    context "with the declared fingerprint setting" do
      around do |example|
        with_app_config(:mobile, **mobile, android_cert_sha256_fingerprints: "AA:BB:CC, DD:EE:FF") { example.run }
      end

      it "splits and trims fingerprints from the declared setting" do
        host! "app.example.test"
        get "/.well-known/assetlinks.json"
        body = JSON.parse(response.body)
        expect(body.first.dig("target", "sha256_cert_fingerprints")).to eq(
          ["AA:BB:CC", "DD:EE:FF"]
        )
      end
    end

    # @lat: [[android-app-links#Why an empty list is announced rather than refused]]
    context "with no fingerprints set, outside production" do
      around do |example|
        with_app_config(:mobile, **mobile, android_cert_sha256_fingerprints: "") { example.run }
      end

      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development")) }

      it "publishes an empty list, never a list holding one empty entry" do
        host! "app.example.test"
        get "/.well-known/assetlinks.json"
        body = JSON.parse(response.body)
        expect(body.first.dig("target", "sha256_cert_fingerprints")).to eq([])
      end
    end
  end

  # @lat: [[well-known-controller-notes#Why the dev tunnel host is appended only in development]]
  describe "dev tunnel host (DEV_TUNNEL_HOST)" do
    let(:tunnel_host) { "sway-dev.example.com" }

    around do |example|
      with_app_config(:ops, dev_tunnel_host: tunnel_host) { example.run }
    end

    context "in development" do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development")) }

      it "serves AASA from the tunnel host" do
        host! tunnel_host
        get "/.well-known/apple-app-site-association"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("webcredentials", "apps")).to eq(["ABCDE12345.app.example.test"])
      end

      it "serves assetlinks from the tunnel host" do
        host! tunnel_host
        get "/.well-known/assetlinks.json"

        expect(response).to have_http_status(:ok)
      end

      it "includes the tunnel origin in the related-origin response" do
        host! tunnel_host
        get "/.well-known/webauthn"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["origins"]).to include("https://#{tunnel_host}")
      end

      it "serves the tunnel host when no host is configured at all" do
        with_app_config(:mobile, **mobile, app_association_hosts: "") do
          with_app_config(:webauthn, related_hosts: "") do
            host! tunnel_host
            get "/.well-known/apple-app-site-association"
            expect(response).to have_http_status(:ok)

            get "/.well-known/webauthn"
            expect(response.parsed_body["origins"]).to eq(["https://#{tunnel_host}"])
          end
        end
      end

      it "still serves the canonical hosts" do
        host! "app.example.test"
        get "/.well-known/webauthn"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["origins"]).to include("https://app.example.test")
      end

      # A spaces-only value is what Sway::Settings::Ops#dev_tunnel_host
      # reads back as nil for -- this proves the association-hosts list
      # widens with nothing when that happens, at the controller boundary.
      it "widens nothing when the tunnel host is spaces only" do
        with_app_config(:ops, dev_tunnel_host: "   ") do
          host! "app.example.test"
          get "/.well-known/webauthn"

          expect(response.parsed_body["origins"]).to eq(["https://example.test", "https://app.example.test"])
        end
      end
    end

    context "outside development" do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production")) }

      it "does not serve AASA from the tunnel host" do
        host! tunnel_host
        get "/.well-known/apple-app-site-association"

        expect(response).to have_http_status(:no_content)
      end

      it "does not serve the related-origin response from the tunnel host" do
        host! tunnel_host
        get "/.well-known/webauthn"

        expect(response).to have_http_status(:no_content)
      end

      it "keeps the canonical related origins unwidened" do
        host! "app.example.test"
        get "/.well-known/webauthn"

        expect(response.parsed_body["origins"]).to eq(["https://example.test", "https://app.example.test"])
      end
    end
  end
end
