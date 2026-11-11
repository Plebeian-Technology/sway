# frozen_string_literal: true

require "rails_helper"

# @lat: [[browser-error-reporting#Development reports stay on this machine]]
RSpec.describe SwayLocalErrorDsn do
  let(:public_id) { "dsnpublicid" }

  describe "addresses on this machine" do
    [
      ["localhost", "http://dsnpublicid@localhost:8482/1"],
      ["127.0.0.1", "http://dsnpublicid@127.0.0.1:8482/1"],
      ["IPv6 loopback", "http://dsnpublicid@[::1]:8482/1"],
      ["the docker host alias", "http://dsnpublicid@host.docker.internal:8482/1"],
      ["the compose service name", "http://dsnpublicid@rustrak:8080/1"]
    ].each do |name, dsn|
      it "accepts #{name}" do
        expect(described_class.local?(dsn)).to be(true)
      end
    end

    it "accepts regardless of how the host is capitalised" do
      expect(described_class.local?("http://#{public_id}@LOCALHOST:8482/1")).to be(true)
    end

    it "ignores surrounding whitespace, which a copied env line often carries" do
      expect(described_class.local?("  http://#{public_id}@localhost:8482/1\n")).to be(true)
    end
  end

  describe "addresses that are not this machine" do
    it "refuses a hosted collector" do
      expect(described_class.local?("https://#{public_id}@errors.example.com/1")).to be(false)
    end

    it "refuses Sentry's own ingest host, which is the likeliest paste" do
      expect(described_class.local?("https://#{public_id}@o123.ingest.us.sentry.io/456")).to be(false)
    end

    # An `include?` on the whole string instead of the host would allow these.
    it "refuses a host that only looks local" do
      expect(described_class.local?("http://#{public_id}@localhost.evil.example.com/1")).to be(false)
      expect(described_class.local?("http://#{public_id}@notlocalhost/1")).to be(false)
      expect(described_class.local?("http://#{public_id}@127.0.0.1.evil.example.com/1")).to be(false)
    end

    it "refuses another machine on the same network" do
      expect(described_class.local?("http://#{public_id}@192.168.1.50:8482/1")).to be(false)
    end
  end

  describe "nothing usable" do
    [["nil", nil], ["an empty string", ""], ["whitespace", "   "], ["not a URL", "not a dsn"]].each do |name, dsn|
      it "refuses #{name}" do
        expect(described_class.local?(dsn)).to be(false)
      end
    end
  end

  # @lat: [[browser-error-reporting#Development reports stay on this machine]]
  describe "the origin a browser would connect to" do
    it "keeps a port the scheme does not imply" do
      public_id = "0123456789abcdef0123456789abcdef"

      expect(described_class.browser_origin("http://#{public_id}@localhost:8482/3"))
        .to eq("http://localhost:8482")
    end

    # A browser compares origins with the default port dropped, so writing it
    # would name an origin that never matches.
    it "drops a port the scheme already implies" do
      public_id = "0123456789abcdef0123456789abcdef"

      expect(described_class.browser_origin("http://#{public_id}@localhost:80/3"))
        .to eq("http://localhost")
      expect(described_class.browser_origin("https://#{public_id}@localhost:443/3"))
        .to eq("https://localhost")
    end

    it "leaves the key out, since an origin is scheme, host and port only" do
      public_id = "0123456789abcdef0123456789abcdef"

      expect(described_class.browser_origin("http://#{public_id}@127.0.0.1:8482/3"))
        .not_to include(public_id)
    end

    # The important one. A policy widened by a pasted-in address would let the
    # browser reach a host this machine has already refused to report to.
    it "answers nothing for an address that is not this machine" do
      public_id = "0123456789abcdef0123456789abcdef"

      expect(described_class.browser_origin("https://#{public_id}@errors.example.com/1")).to be_nil
      expect(described_class.browser_origin("https://#{public_id}@o123.ingest.us.sentry.io/456")).to be_nil
      expect(described_class.browser_origin("http://#{public_id}@192.168.1.50:8482/1")).to be_nil
    end

    [["nil", nil], ["an empty string", ""], ["not a URL", "not a dsn"]].each do |name, dsn|
      it "answers nothing for #{name}" do
        expect(described_class.browser_origin(dsn)).to be_nil
      end
    end
  end
end
