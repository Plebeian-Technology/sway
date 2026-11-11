# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sway::Release do
  # Release reads plain ENV["..."] keys. Each example fakes only the keys it
  # cares about; every other key still comes from the real environment.
  describe "with deploy-time ENV set (production-shaped)" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SWAY_RELEASE_VERSION").and_return("8")
      allow(ENV).to receive(:[]).with("SWAY_RELEASE_SHA").and_return("963d9cebdeadbeef")
      allow(ENV).to receive(:[]).with("SWAY_PREVIOUS_SHA").and_return("4e78f6d4cafef00d")
      allow(ENV).to receive(:[]).with("SWAY_DEPLOYED_AT").and_return("2026-06-03T13:05:00Z")
    end

    it "exposes the integer version" do
      expect(described_class.version).to eq(8)
    end

    it "exposes the full and short current sha" do
      expect(described_class.sha).to eq("963d9cebdeadbeef")
      expect(described_class.short_sha).to eq("963d9ceb")
    end

    it "exposes the full and short previous-release sha" do
      expect(described_class.previous_sha).to eq("4e78f6d4cafef00d")
      expect(described_class.previous_short_sha).to eq("4e78f6d4")
    end

    it "parses the deploy timestamp" do
      expect(described_class.deployed_at).to eq(Time.utc(2026, 6, 3, 13, 5, 0))
    end

    it "serializes to a json-safe hash that round-trips the timestamp" do
      json = described_class.to_sway_json

      expect(json).to include(
        version: 8,
        sha: "963d9cebdeadbeef",
        short_sha: "963d9ceb",
        previous_sha: "4e78f6d4cafef00d",
        previous_short_sha: "4e78f6d4"
      )
      expect(Time.iso8601(json[:deployed_at])).to eq(Time.utc(2026, 6, 3, 13, 5, 0))
    end
  end

  # @lat: [[system-shape#Deployment#The release fingerprint never runs a diff converter]]
  describe "whether the build matches the commit it names" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(described_class).to receive(:git).and_return(nil)
    end

    it "says the build is the commit when the tree was clean at build time" do
      allow(ENV).to receive(:[]).with("SWAY_UNCOMMITTED_DIGEST").and_return("")

      expect(described_class.uncommitted_digest).to be_nil
      expect(described_class.built_from_committed_tree?).to be(true)
      expect(described_class.to_sway_json[:uncommitted_digest]).to be_nil
      expect(described_class.to_sway_json[:built_from_committed_tree]).to be(true)
    end

    it "names the extra changes when the tree was dirty at build time" do
      allow(ENV).to receive(:[]).with("SWAY_UNCOMMITTED_DIGEST").and_return("a1b2c3d4")

      expect(described_class.uncommitted_digest).to eq("a1b2c3d4")
      expect(described_class.built_from_committed_tree?).to be(false)
      expect(described_class.to_sway_json[:uncommitted_digest]).to eq("a1b2c3d4")
      expect(described_class.to_sway_json[:built_from_committed_tree]).to be(false)
    end

    # Collapsing unset into empty is what would let a page claim a clean tree.
    it "says it does not know when no deploy recorded the answer" do
      allow(ENV).to receive(:[]).with("SWAY_UNCOMMITTED_DIGEST").and_return(nil)

      expect(described_class.built_from_committed_tree?).to be_nil
      expect(described_class.to_sway_json[:built_from_committed_tree]).to be_nil
    end

    # @lat: [[system-shape#Deployment#The release fingerprint never runs a diff converter]]
    it "never shells out to git to answer" do
      allow(ENV).to receive(:[]).with("SWAY_UNCOMMITTED_DIGEST").and_return(nil)
      expect(described_class).not_to receive(:git)

      described_class.uncommitted_digest
      described_class.built_from_committed_tree?
    end
  end

  describe "with ENV unset (dev/test shape)" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SWAY_RELEASE_VERSION").and_return(nil)
      allow(ENV).to receive(:[]).with("SWAY_RELEASE_SHA").and_return(nil)
      allow(ENV).to receive(:[]).with("SWAY_PREVIOUS_SHA").and_return(nil)
      allow(ENV).to receive(:[]).with("SWAY_DEPLOYED_AT").and_return(nil)
      # Stop the dev-only fallback from running a real git command during tests.
      allow(described_class).to receive(:git).and_return(nil)
    end

    it "returns nil for version, previous sha, and deploy time" do
      expect(described_class.version).to be_nil
      expect(described_class.previous_sha).to be_nil
      expect(described_class.deployed_at).to be_nil
    end

    it "falls back to git for the sha (nil when git is unavailable)" do
      expect(described_class.sha).to be_nil
      expect(described_class.short_sha).to be_nil
    end
  end

  # @lat: [[release-git-fallback-and-caching#Why to_sway_json reads sha once]]
  describe "subprocess count for the git fallback" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SWAY_RELEASE_SHA").and_return(nil)
    end

    it "shells out to git exactly once per to_sway_json call" do
      allow(Sway::Subprocess).to receive(:capture3).and_call_original

      described_class.to_sway_json

      expect(Sway::Subprocess).to have_received(:capture3).with("git", any_args).once
    end
  end

  describe "with malformed ENV" do
    it "returns nil for a non-integer version" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SWAY_RELEASE_VERSION").and_return("not-a-number")

      expect(described_class.version).to be_nil
    end

    it "returns nil for an unparseable deploy timestamp" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SWAY_DEPLOYED_AT").and_return("garbage")

      expect(described_class.deployed_at).to be_nil
    end
  end
end
