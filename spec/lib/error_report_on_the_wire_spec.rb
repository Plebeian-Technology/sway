# frozen_string_literal: true

require "rails_helper"
require "support/fake_error_collector"

# @lat: [[local-error-reporting-design#Why one spec sends a real request instead of reading a report back in memory]]
RSpec.describe "an error report on the wire" do
  # Not a real project, and nothing is contacted: WebMock answers the request.
  let(:collector_dsn) { "http://dsnpublicid@localhost:8482/1" }
  let(:collector_endpoint) { "http://localhost:8482/api/1/envelope/" }

  let(:planted_key) { ["sk", "ant", "api03NOTREAL0000deadbeefTESTKEY"].join("-") }
  let(:planted_email) { "planted.person@example-not-real.org" }
  let(:planted_phone) { "410-555-0142" }

  # Sentry.close nils the main hub, so closing one this spec did not open would
  # switch reporting off for every example ordered after it.
  around do |example|
    already_initialized = Sentry.initialized?
    Sentry.init do |config|
      SwayLocalErrorReporting.apply(config, dsn: collector_dsn)
      # Send on the calling thread. The gem's default hands the report to a
      # background worker, and the example would end before it left.
      config.background_worker_threads = 0
    end
    begin
      example.run
    ensure
      Sentry.close
      load Rails.root.join("config", "initializers", "sentry.rb").to_s if already_initialized
    end
  end

  # Catches every request the gem's own transport builds — after compression and
  # after the headers are written, which is where the fault lived.
  def catch_reports
    caught = []
    stub_request(:post, collector_endpoint).to_return do |request|
      caught << [request.headers, request.body]
      {status: 200, body: '{"id":"00000000000000000000000000000000"}'}
    end

    yield

    raise "the app sent nothing at all" if caught.empty?
    caught
  end

  # Reads EVERY request through the collector, so an envelope it would refuse
  # fails the example even when the error itself rode in a different one.
  def stored_events(&block)
    collector = FakeErrorCollector.new
    catch_reports(&block).filter_map { |headers, body| collector.receive(headers, body) }
  end

  def stored_error(&block)
    stored_events(&block).first || raise("nothing the app sent carried an error")
  end

  def send_probe
    Sentry.capture_exception(StandardError.new("wire probe"))
  end

  it "sends something the collector accepts" do
    expect { stored_events { send_probe } }.not_to raise_error
  end

  # The exact refusal that left the Ruby half dead. Reverting
  # SwayGzipOnlyTransport#should_compress? to the gem's answer fails this.
  it "never names an encoding the collector cannot read" do
    encodings = catch_reports { send_probe }.map do |headers, _body|
      headers.find { |key, _| key.to_s.casecmp?("Content-Encoding") }&.last
    end

    expect(encodings.uniq).to eq(["gzip"])
  end

  it "carries the error itself, so the report is worth storing" do
    expect(stored_error { send_probe }.to_json).to include("StandardError")
  end

  it "carries no planted key, email or phone once it has left the app" do
    message = "failed for #{planted_email} / #{planted_phone} / #{planted_key}"
    stored = stored_error { Sentry.capture_exception(StandardError.new(message)) }.to_json

    expect(stored).not_to include(planted_key)
    expect(stored).not_to include(planted_email)
    expect(stored).not_to include(planted_phone)
  end

  it "still says which environment it came from" do
    expect(stored_error { send_probe }["environment"]).to eq("test")
  end

  # Each rule the collector applies, proved to bite on its own. Without these
  # the examples above would pass against a reader that refuses nothing.
  describe "the rules the collector applies" do
    it "refuses the empty encoding the gem writes when it does not compress" do
      expect { FakeErrorCollector.new.receive({"Content-Encoding" => ""}, "{}") }
        .to raise_error(FakeErrorCollector::Refused, /Unsupported Content-Encoding/)
    end

    it "refuses an event_id that something rewrote" do
      expect { FakeErrorCollector.new.receive({}, %({"event_id":"[FILTERED_PHONE]abcdef"})) }
        .to raise_error(FakeErrorCollector::Refused, /event_id/)
    end

    it "refuses a request whose headers arrived as a string" do
      envelope = [
        %({"event_id":"1699999999abcdef1699999999abcdef"}),
        %({"type":"event"}),
        %({"request":{"headers":"[FILTERED]"}})
      ].join("\n")

      expect { FakeErrorCollector.new.receive({}, envelope) }
        .to raise_error(FakeErrorCollector::Refused, /must be a map/)
    end

    it "refuses an empty fingerprint, which groups every error into one" do
      envelope = [
        %({"event_id":"1699999999abcdef1699999999abcdef"}),
        %({"type":"event"}),
        %({"fingerprint":[]})
      ].join("\n")

      expect { FakeErrorCollector.new.receive({}, envelope) }
        .to raise_error(FakeErrorCollector::Refused, /fingerprint/)
    end

    it "accepts an absent encoding, which means the body is not compressed" do
      envelope = %({"event_id":"1699999999abcdef1699999999abcdef"})

      expect { FakeErrorCollector.new.receive({}, envelope) }.not_to raise_error
    end
  end
end
