# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "seedable")

RSpec.describe Seedable do
  let(:dummy_class) { Class.new { include Seedable }.new }

  describe "#seed_or_skip?" do
    context "with a new (unpersisted) record" do
      let(:record) { build(:legislator) }

      it "returns false (seed the new record) regardless of force" do
        expect(dummy_class.seed_or_skip?(record, force: false)).to be(false)
        expect(dummy_class.seed_or_skip?(record, force: true)).to be(false)
      end
    end

    context "with a persisted record and force: true" do
      let(:record) { create(:legislator) }

      it "returns false (force bypasses all checks)" do
        # Set up an edit made outside the seeder, so the only reason false comes
        # back is force
        record.update_columns(last_seeded_at: 1.hour.ago)
        expect(dummy_class.seed_or_skip?(record, force: true)).to be(false)
      end
    end

    context "with a persisted record whose last_seeded_at is nil" do
      let(:record) { create(:legislator) }

      it "returns false (never seeded before; seed it)" do
        expect(record.last_seeded_at).to be_nil
        expect(dummy_class.seed_or_skip?(record, force: false)).to be(false)
      end
    end

    context "with a persisted record whose updated_at == last_seeded_at (clean)" do
      let(:record) do
        r = create(:legislator)
        r.update_columns(last_seeded_at: r.updated_at)
        r.reload
      end

      it "returns false (clean, safe to re-seed)" do
        expect(dummy_class.seed_or_skip?(record, force: false)).to be(false)
      end
    end

    context "with a persisted record whose updated_at != last_seeded_at (out-of-band edited)" do
      let(:record) do
        r = create(:legislator)
        r.update_columns(last_seeded_at: 1.hour.ago)
        r.reload
      end

      it "returns true (caller must skip)" do
        expect(dummy_class.seed_or_skip?(record, force: false)).to be(true)
      end
    end
  end

  describe "#stamp_seeded_at!" do
    let(:record) { create(:legislator) }

    it "sets last_seeded_at equal to record.updated_at" do
      record.update_columns(last_seeded_at: nil)
      dummy_class.stamp_seeded_at!(record)
      expect(record.reload.last_seeded_at).to eq(record.updated_at)
    end

    it "does not fire after_commit callbacks (uses update_columns)" do
      # Legislator queues MirrorExternalAssetJob from an after_commit callback
      # whenever photo_url changes. stamp_seeded_at! writes only last_seeded_at,
      # so photo_url never changes here — but we still confirm it goes through
      # update_columns by checking that updated_at was not bumped.
      record.update_columns(last_seeded_at: 1.hour.ago)
      original_updated_at = record.updated_at
      dummy_class.stamp_seeded_at!(record)
      expect(record.reload.updated_at).to eq(original_updated_at)
    end
  end
end
