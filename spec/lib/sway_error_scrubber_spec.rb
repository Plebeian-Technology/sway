# frozen_string_literal: true

require "rails_helper"
require "sentry/test_helper"

# @lat: [[browser-error-reporting#Development reports stay on this machine]]
RSpec.describe SwayErrorScrubber do
  # Assembled, not written out: gitleaks scans this file and an sk-ant- literal
  # is a finding whether or not it is real.
  let(:planted_key) { ["sk", "ant", "api03NOTREAL0000deadbeefTESTKEY"].join("-") }
  let(:planted_email) { "planted.person@example-not-real.org" }
  let(:planted_phone) { "410-555-0142" }

  describe ".scrub_text" do
    it "removes an Anthropic API key" do
      expect(described_class.scrub_text("upstream refused: #{planted_key}"))
        .to eq("upstream refused: [FILTERED_KEY]")
    end

    it "removes an email address" do
      expect(described_class.scrub_text("could not notify #{planted_email}"))
        .to eq("could not notify [FILTERED_EMAIL]")
    end

    ["410-555-0142", "(410) 555-0142", "410.555.0142", "+1 410 555 0142", "4105550142"].each do |phone|
      it "removes a phone number written as #{phone}" do
        expect(described_class.scrub_text("sms to #{phone} failed")).to eq("sms to [FILTERED_PHONE] failed")
      end
    end

    it "caps one huge value so a whole column cannot ride along" do
      result = described_class.scrub_text("x" * 50_000)

      expect(result.length).to be < 3_000
      expect(result).to include("truncated")
    end

    # Deliberate over-reach, pinned so it is a decision rather than a surprise.
    # Sway stores phone numbers as bare digits (ADMIN_PHONES is digits only), so
    # the pattern has to match them, and any other 10-digit run goes with them.
    # Losing an id from a report is cheaper than keeping a phone number.
    it "also scrubs any bare 10-digit run, such as an id or a timestamp" do
      expect(described_class.scrub_text("row 1699999999 failed")).to eq("row [FILTERED_PHONE] failed")
    end

    it "leaves shorter and longer digit runs alone" do
      expect(described_class.scrub_text("bill 62 row 123456789012 ok")).to eq("bill 62 row 123456789012 ok")
    end

    # The email pattern is quadratic, so redacting before capping was seconds
    # on a long string. Capping first holds every pattern to ~2KB.
    it "stays fast on a huge string instead of blocking on backtracking" do
      huge = "a.b-c_d%e+f" * 5_000

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      described_class.scrub_text(huge)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(elapsed).to be < 0.25
    end

    it "leaves an ordinary message alone" do
      message = "undefined method 'bills' for nil"

      expect(described_class.scrub_text(message)).to eq(message)
    end
  end

  describe ".deep_scrub" do
    it "reaches values nested inside arrays and hashes" do
      scrubbed = described_class.deep_scrub({a: [{b: "key #{planted_key}"}]})

      expect(scrubbed.to_s).not_to include(planted_key)
    end

    %w[cookie cookies headers authorization token password secret].each do |key|
      it "drops #{key} whole, since it carries a session or credential" do
        scrubbed = described_class.deep_scrub({key => "planted-secret-value"})

        expect(scrubbed[key]).to eq("[FILTERED]")
      end
    end

    it "drops them whatever their capitalisation" do
      expect(described_class.deep_scrub({"Cookie" => "planted-secret-value"})["Cookie"]).to eq("[FILTERED]")
    end

    # Sentry's protocol declares request.headers a map. A string there is
    # invalid, and Android's native SDK throws on it and loses the whole error —
    # observed on an Android emulator. The collector accepts one, so only the
    # phone ever complains; all three scrubbers keep the shape.
    it "keeps a dropped map a map rather than turning it into a string" do
      scrubbed = described_class.deep_scrub({"headers" => {"Cookie" => "planted-secret-value"}})

      expect(scrubbed["headers"]).to eq({})
    end

    it "keeps a dropped list a list" do
      scrubbed = described_class.deep_scrub({"cookies" => ["a=1", "b=2"]})

      expect(scrubbed["cookies"]).to eq([])
    end

    it "stops at a depth limit rather than recursing without bound" do
      # @type var deep: untyped
      deep = "bottom"
      30.times { deep = {nested: deep} }

      expect(described_class.deep_scrub(deep).to_s).to include("FILTERED_TOO_DEEP")
    end
  end

  # The real gate: a genuine exception through a real Sentry client, asserting
  # on the serialized envelope rather than on the scrubber in isolation. This
  # needs no collector running.
  describe "an exception carried through Sentry" do
    include Sentry::TestHelper

    # setup_sentry_test dups the LIVE config, so a real Sentry.init has to apply
    # the settings under test first.
    around do |example|
      # Sentry.close nils the main hub and stops the worker, so closing one this
      # spec did not open would disable reporting for every example ordered
      # after it — which is why the reload below is conditional.
      already_initialized = Sentry.initialized?
      begin
        Sentry.init { |config| SwayLocalErrorReporting.apply(config, dsn: "http://dsnpublicid@localhost:8482/1") }
        setup_sentry_test
        example.run
      ensure
        teardown_sentry_test
        Sentry.close
        load Rails.root.join("config", "initializers", "sentry.rb").to_s if already_initialized
      end
    end

    def captured_payload(message)
      Sentry.capture_exception(StandardError.new(message))
      sentry_events.last.to_json_compatible.to_json
    end

    it "removes a planted key, email and phone from the exception message" do
      payload = captured_payload("failed for #{planted_email} / #{planted_phone} / #{planted_key}")

      expect(payload).not_to include(planted_key)
      expect(payload).not_to include(planted_email)
      expect(payload).not_to include(planted_phone)
    end

    # The leak this was written after. sentry-rails puts :params in a
    # start_processing.action_controller breadcrumb, and filter_parameter_logging
    # does not filter street/city/postal_code — which is what the registration
    # form posts. Nothing else in the scrubber touched breadcrumbs.
    it "scrubs a breadcrumb carrying controller params" do
      Sentry.add_breadcrumb(
        Sentry::Breadcrumb.new(
          category: "start_processing.action_controller",
          message: "registering #{planted_email}",
          data: {params: {"street" => "100 N Holliday St", "phone" => planted_phone, "email" => planted_email}}
        )
      )

      payload = captured_payload("registration blew up")

      expect(payload).not_to include(planted_email)
      expect(payload).not_to include(planted_phone)
    end

    it "drops a cookie header sitting inside breadcrumb data" do
      Sentry.add_breadcrumb(
        Sentry::Breadcrumb.new(category: "request", data: {"cookie" => "session=PLANTEDSESSIONVALUE"})
      )

      expect(captured_payload("boom")).not_to include("PLANTEDSESSIONVALUE")
    end

    it "scrubs a captured message, which is where capture_message puts its text" do
      Sentry.capture_message("could not reach #{planted_email}")

      expect(sentry_events.last.to_json_compatible.to_json).not_to include(planted_email)
    end

    # @lat: [[error-scrubber-empty-fingerprint-bug#Why scrubErrorEvent (the web beforeSend hook) also removes it]]
    it "sends no fingerprint at all, rather than an empty one" do
      Sentry.capture_exception(StandardError.new("boom"))

      expect(sentry_events.last.to_json_compatible).not_to have_key("fingerprint")
    end

    it "keeps a fingerprint the app really chose" do
      Sentry.capture_exception(StandardError.new("boom")) { |scope| scope.set_fingerprint(["checkout"]) }

      expect(sentry_events.last.to_json_compatible["fingerprint"]).to eq(["checkout"])
    end

    # A rewritten event_id is not a valid id, so the collector drops the
    # envelope and the error vanishes.
    it "leaves the event_id intact" do
      Sentry.capture_exception(StandardError.new("boom"))
      event = sentry_events.last

      expect(event.event_id).to match(/\A[0-9a-f]{32}\z/)
    end

    it "still reports the error class, so the report is worth keeping" do
      expect(captured_payload("something broke")).to include("StandardError")
    end

    it "sends no local variables, which is where testimony would ride" do
      expect(Sentry.configuration.include_local_variables).to be(false)
    end

    # The scenario from the issue: saving testimony posts the whole text. The
    # marker is deliberately not something any pattern would catch, so this
    # tests that the BODY does not travel, not that the scrubber cleaned it.
    it "sends no request body, which is what saving testimony posts" do
      marker = "PLANTEDTESTIMONYBODYMARKER"
      env = Rack::MockRequest.env_for("/bills/62/testimony", input: "testimony=#{marker}")
      env["REQUEST_METHOD"] = "POST"
      env["CONTENT_TYPE"] = "application/x-www-form-urlencoded"
      env["HTTP_COOKIE"] = "session=#{marker}COOKIE"
      env["HTTP_AUTHORIZATION"] = "Bearer #{marker}TOKEN"
      Sentry.get_current_scope.set_rack_env(env)

      payload = captured_payload("save failed")

      expect(payload).not_to include(marker)
    end

    it "sends no personal information by default" do
      expect(Sentry.configuration.send_default_pii).to be(false)
    end

    it "asks for no tracing or profiling, which the collector discards anyway" do
      expect(Sentry.configuration.traces_sample_rate).to eq(0.0)
      expect(Sentry.configuration.profiles_sample_rate).to eq(0.0)
    end
  end

  # Pinned so nobody assumes addresses are covered. What keeps testimony out is
  # upstream: no bodies, headers or local variables are sent.
  describe "the limit of what a pattern can find" do
    it "does NOT remove a street address written as prose" do
      address = "100 N Holliday St"

      expect(described_class.scrub_text("geocoding failed for #{address}")).to include(address)
    end
  end
end
