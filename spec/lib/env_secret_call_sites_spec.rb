# frozen_string_literal: true

require "rails_helper"

# @lat: [[env-secret-blank-value-handling#Why EnvSecret.fetch! raises instead of returning nil]]
RSpec.describe "ENV secret whitespace stripping" do
  describe "Sway::TwilioClient.build (TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN)" do
    it "hands Twilio the stripped sid and token" do
      with_env("TWILIO_ACCOUNT_SID" => "AC123\n", "TWILIO_AUTH_TOKEN" => "tok456\n") do
        expect(Twilio::REST::Client).to receive(:new).with("AC123", "tok456")

        Sway::TwilioClient.build
      end
    end
  end

  describe "GitHubPrService (GITHUB_TOKEN)" do
    it "hands Octokit the stripped token" do
      with_env("GITHUB_TOKEN" => "ghp_abc\n", "GITHUB_REPO" => "owner/repo\n") do
        expect(Octokit::Client).to receive(:new).with(access_token: "ghp_abc")

        GitHubPrService.new
      end
    end

    it "still raises KeyError when the token is missing" do
      with_env("GITHUB_TOKEN" => nil, "GITHUB_REPO" => "owner/repo") do
        expect { GitHubPrService.new }.to raise_error(KeyError, /GITHUB_TOKEN/)
      end
    end

    it "treats a whitespace-only token as missing rather than authenticating with it" do
      with_env("GITHUB_TOKEN" => " \n", "GITHUB_REPO" => "owner/repo") do
        expect { GitHubPrService.new }.to raise_error(KeyError, /GITHUB_TOKEN/)
      end
    end

    # @lat: [[github-pr-service-design#Why GITHUB_REPO is read with EnvSecret.read, not ENV.fetch with a block]]
    it "hands Octokit the stripped repo slug" do
      with_env("GITHUB_TOKEN" => "ghp_abc", "GITHUB_REPO" => "owner/repo\n") do
        client = instance_double(Octokit::Client)
        allow(Octokit::Client).to receive(:new).and_return(client)
        expect(client).to receive(:repo).with("owner/repo")
          .and_return(double(default_branch: "main"))

        GitHubPrService.new.send(:default_branch)
      end
    end

    # The other half of what the old block form could not catch. It checks the
    # SHAPE of the derived repository name, not this checkout's actual remote, so
    # the test does not care which clone it runs in.
    it "treats a blank GITHUB_REPO as unset and derives the slug from the git remote" do
      with_env("GITHUB_TOKEN" => "ghp_abc", "GITHUB_REPO" => "") do
        client = instance_double(Octokit::Client)
        allow(Octokit::Client).to receive(:new).and_return(client)
        expect(client).to receive(:repo)
          .with(a_string_matching(%r{\A[^/\s]+/[^/\s]+\z}))
          .and_return(double(default_branch: "main"))

        GitHubPrService.new.send(:default_branch)
      end
    end
  end

  describe "PushNotificationSubscription#vapid (VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY)" do
    it "signs with the stripped key pair" do
      with_env("VAPID_PUBLIC_KEY" => "pub\n", "VAPID_PRIVATE_KEY" => "priv\n") do
        vapid = PushNotificationSubscription.new.send(:vapid)

        expect(vapid[:public_key]).to eq("pub")
        expect(vapid[:private_key]).to eq("priv")
      end
    end
  end

  # @lat: [[outbound-email#Outbound email#A trailing newline reads as a revoked key]]
  describe "UserLegislatorEmail#sendable? (RESEND_EMAIL_API_KEY)" do
    let(:sendable_email) do
      # is_email_verified is set AFTER the record is created, not handed to the
      # factory. User has a before_create hook that forces it, and the other
      # verification flags, to false: verification is a later step, not something
      # an account is born with. Pass it to the factory and it is quietly lost.
      user = create(:user, email: "voter@example.test")
      user.update!(is_email_verified: true)

      legislator = create(:legislator, email: "rep@example.test")
      bill = create(:bill)

      build(
        :user_legislator_email,
        user_legislator: create(:user_legislator, user: user, legislator: legislator),
        bill: bill
      )
    end

    it "is sendable when the key is present and every other precondition holds" do
      with_env("RESEND_EMAIL_API_KEY" => "re_not-a-real-key\n") do
        expect(sendable_email.sendable?).to eq(true)
      end
    end

    it "does not treat a whitespace-only key as a usable credential" do
      with_env("RESEND_EMAIL_API_KEY" => " \n") do
        expect(sendable_email.sendable?).to eq(false)
      end
    end
  end

  # @lat: [[outbound-email#Outbound email#A trailing newline reads as a revoked key]]
  describe "Resend API key (RESEND_EMAIL_API_KEY, config/initializers/resend.rb)" do
    def initializer_reads
      ENV["RESEND_EMAIL_API_KEY"].to_s.strip.presence
    end

    it "carries no trailing newline through to the credential" do
      with_env("RESEND_EMAIL_API_KEY" => "re_not-a-real-key\n") do
        expect(initializer_reads).to eq("re_not-a-real-key")
      end
    end

    it "reads a whitespace-only key as absent rather than as an empty credential" do
      with_env("RESEND_EMAIL_API_KEY" => " \n") do
        expect(initializer_reads).to be_nil
      end
    end

    it "reads an unset key as absent" do
      with_env("RESEND_EMAIL_API_KEY" => nil) do
        expect(initializer_reads).to be_nil
      end
    end
  end

  # The one that matters most. A newline here does not produce a 401. It quietly
  # changes every signature the app computes AND checks, so everything looks fine
  # until the day the secret is read without it.
  describe "ApiKey.hmac_secret_key (API_KEY_HMAC_SECRET_KEY)" do
    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    end

    it "keys the HMAC with the stripped secret" do
      with_env("API_KEY_HMAC_SECRET_KEY" => "s3cr3t\n") do
        expect(ApiKey.hmac_secret_key).to eq("s3cr3t")
      end
    end

    # @lat: [[env-secret-blank-value-handling#Why EnvSecret.fetch! raises instead of returning nil]]
    it "reports a whitespace-only secret as MISSING so the fail-loud guards still fire" do
      with_env("API_KEY_HMAC_SECRET_KEY" => "  \n") do
        expect(ApiKey.hmac_secret_key).to be_nil
        # Checked by exact class and message, not the bare StandardError this
        # used to settle for. Nothing gets signed with a blank secret, and the
        # error names the variable an operator has to set — which is the whole
        # point of raising instead of carrying on.
        expect { ApiKey.authenticate_by_token!("anything") }
          .to raise_error(ApiKey::MissingHmacSecretError, /API_KEY_HMAC_SECRET_KEY/)
      end
    end

    it "still resolves to the fixed test secret under RAILS_ENV=test" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))

      with_env("API_KEY_HMAC_SECRET_KEY" => "ignored\n") do
        expect(ApiKey.hmac_secret_key).to eq("test")
      end
    end
  end

  # @lat: [[new-relic-license-key-boot-normalization#Why this credential skips EnvSecret]]
  describe "NEW_RELIC_LICENSE_KEY (normalised in config/boot.rb)" do
    def boot_with(value)
      env = {
        "NEW_RELIC_LICENSE_KEY" => value,
        "SWAY_ALLOW_HOST_RAILS" => "1",
        "RAILS_ENV" => "test"
      }
      Bundler.with_unbundled_env do
        IO.popen(
          env,
          ["ruby", "-e", 'require "./config/boot"; print ENV["NEW_RELIC_LICENSE_KEY"].inspect'],
          chdir: Rails.root.to_s,
          &:read
        )
      end
    end

    it "strips the variable itself, which is what the agent actually reads" do
      expect(boot_with("nrlk_abc123\n")).to eq('"nrlk_abc123"')
    end

    it "strips a leading newline, the one shape that breaks the yaml load outright" do
      expect(boot_with("\nnrlk_abc123")).to eq('"nrlk_abc123"')
    end

    # Removed, not set to "". An empty string is still a value: EnvironmentSource
    # would take it and override the yaml with a blank license. Absent is the
    # honest way to say "no credential was supplied".
    it "deletes a whitespace-only value rather than blanking it" do
      expect(boot_with(" \n")).to eq("nil")
    end

    # The evidence for why fixing the yaml alone would not have worked, written
    # as a runnable claim: if a future newrelic_rpm starts stripping the value
    # here, this example fails and the boot.rb clean-up can be deleted.
    it "documents that newrelic_rpm reads the variable unstripped and outranks the yaml" do
      # newrelic_rpm belongs to the production gem group, so under `bundle exec`
      # it is on the load path, but Bundler does not require it in test.
      require "newrelic_rpm"

      with_env("NEW_RELIC_LICENSE_KEY" => "nrlk_abc123\n") do
        source = NewRelic::Agent::Configuration::EnvironmentSource.new
        expect(source[:license_key]).to eq("nrlk_abc123\n")
      end

      path = NewRelic::Agent::Configuration::Manager.instance_method(:config_stack)
        .source_location&.first
      stack = File.read(path.to_s)
      expect(stack).to match(/@environment_source,.*@server_source,.*@manual_source,.*@yaml_source/m)
    end
  end

  # @lat: [[env-secret-blank-value-handling#Why a credential is read once and reused, not read again at the point of use]]
  describe "Llm::ClaudeConnection.api_key (ANTHROPIC_API_KEY)" do
    it "returns the stripped key" do
      with_env("ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key\n") do
        expect(Llm::ClaudeConnection.send(:api_key)).to eq("sk-ant-not-a-real-key")
      end
    end

    # Blank has to look exactly like unset. Returning "" would send an empty
    # x-api-key header and earn a 401 that names nothing.
    it "raises the retryable transport error, naming the variable, when blank" do
      with_env("ANTHROPIC_API_KEY" => "  \n") do
        expect { Llm::ClaudeConnection.send(:api_key) }
          .to raise_error(Llm::TransportError, /ANTHROPIC_API_KEY/)
      end
    end
  end

  describe "Scraper::OpenStates::Senate::ApiConnector#auth (OPEN_STATES_API_KEY)" do
    it "returns the stripped key" do
      with_env("OPEN_STATES_API_KEY" => "os_key\n") do
        connector = Scraper::OpenStates::Senate::LegislatorVotes.allocate

        expect(connector.send(:auth)).to eq("os_key")
      end
    end
  end

  describe "Authentication#service_sid (TWILIO_VERIFY_SERVICE_SID)" do
    it "returns the stripped sid" do
      with_env("TWILIO_VERIFY_SERVICE_SID" => "VA789\n") do
        controller = PhoneVerificationController.new

        expect(controller.send(:service_sid)).to eq("VA789")
      end
    end
  end

  describe "SwayRegistrationService (OPEN_STATES_API_KEY)" do
    let(:sway_locale) { create(:sway_locale) }
    let(:user) { create(:user) }
    let(:address) { create(:address, latitude: 39.29, longitude: -76.61) }
    let(:service) do
      SwayRegistrationService.new(user, address, sway_locale, invited_by_id: nil, async: false)
    end

    it "sends the stripped key as the OpenStates apikey query param" do
      with_env("OPEN_STATES_API_KEY" => "os_key\n") do
        connection = instance_double(Faraday::Connection)
        allow(Sway::FaradayStack).to receive(:open_states).and_return(connection)
        expect(connection).to receive(:get).with(
          "people.geo",
          hash_including(apikey: "os_key")
        ).and_return(instance_double(Faraday::Response, status: 200, body: "{}"))

        service.send(:find_legislators_from_open_states_geo_endpoint)
      end
    end

    # Also correct before the fix: the check is `.blank?`, which already treats
    # whitespace as empty. Pinned so the fix cannot break it.
    it "still degrades to [] when the key is whitespace-only" do
      with_env("OPEN_STATES_API_KEY" => " \n") do
        expect(Sway::FaradayStack).not_to receive(:open_states)

        expect(service.send(:find_legislators_from_open_states_geo_endpoint)).to eq([])
      end
    end

    # @lat: [[env-secret-blank-value-handling#Why a credential is read once and reused, not read again at the point of use]]
    it "sends the same value that cleared the guard, having read it once" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPEN_STATES_API_KEY").and_return("first\n", "second\n")

      connection = instance_double(Faraday::Connection)
      allow(Sway::FaradayStack).to receive(:open_states).and_return(connection)
      expect(connection).to receive(:get).with(
        "people.geo",
        hash_including(apikey: "first")
      ).and_return(instance_double(Faraday::Response, status: 200, body: "{}"))

      service.send(:find_legislators_from_open_states_geo_endpoint)
    end
  end

  describe "Legislation::Adapters::GenericRosterAdapter (OPEN_STATES_API_KEY)" do
    let(:adapter) do
      Legislation::Adapters::GenericRosterAdapter.new(
        retrieval: "open_states",
        parsing: "open_states",
        jurisdiction: "Maryland"
      )
    end
    let(:connection) { instance_double(Faraday::Connection) }

    it "sends the stripped key in the X-API-KEY header" do
      with_env("OPEN_STATES_API_KEY" => "test-key\n") do
        response = instance_double(Faraday::Response, status: 200, body: '{"results": []}')
        expect(connection).to receive(:get).with(
          "/people",
          hash_including(per_page: 50, page: 1, jurisdiction: "Maryland"),
          {"X-API-KEY" => "test-key"}
        ).and_return(response)

        adapter.send(:retrieve_open_states_payload, connection)
      end
    end

    it "raises KeyError when OPEN_STATES_API_KEY is whitespace-only" do
      with_env("OPEN_STATES_API_KEY" => "  \n") do
        expect(connection).not_to receive(:get)

        expect {
          adapter.send(:retrieve_open_states_payload, connection)
        }.to raise_error(KeyError, /OPEN_STATES_API_KEY/)
      end
    end
  end

  describe "BraveSearch::Client (BRAVE_SEARCH_API_KEY)" do
    let(:connection) { instance_double(Faraday::Connection) }
    let(:client) { BraveSearch::Client.new(connection: connection) }

    it "sends the stripped key in the X-Subscription-Token header" do
      with_env("BRAVE_SEARCH_API_KEY" => "test-brave-key\n") do
        response = instance_double(Faraday::Response, status: 200, body: '{"web": {"results": []}}')
        expect(connection).to receive(:get).with(
          "/res/v1/web/search",
          hash_including(q: "24-0012 Housing site:thebanner.com", count: 20),
          {"X-Subscription-Token" => "test-brave-key"}
        ).and_return(response)

        client.search(query: "24-0012 Housing", allowed_domains: ["thebanner.com"])
      end
    end

    it "raises KeyError when BRAVE_SEARCH_API_KEY is whitespace-only" do
      with_env("BRAVE_SEARCH_API_KEY" => "  \n") do
        expect(connection).not_to receive(:get)

        expect {
          client.search(query: "24-0012 Housing", allowed_domains: ["thebanner.com"])
        }.to raise_error(KeyError, /BRAVE_SEARCH_API_KEY/)
      end
    end

    it "raises KeyError when BRAVE_SEARCH_API_KEY is nil" do
      with_env("BRAVE_SEARCH_API_KEY" => nil) do
        expect(connection).not_to receive(:get)

        expect {
          client.search(query: "24-0012 Housing", allowed_domains: ["thebanner.com"])
        }.to raise_error(KeyError, /BRAVE_SEARCH_API_KEY/)
      end
    end
  end
end
