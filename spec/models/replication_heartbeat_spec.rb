# frozen_string_literal: true

require "rails_helper"

# The table holds exactly one row, ever, at primary key 1, enforced by
# ReplicationHeartbeat's validation and by a database check constraint below
# it.
# == Schema Information
#
# Table name: replication_heartbeats
# Database name: primary
#
#  id                         :integer          not null, primary key
#  checked_at                 :datetime         not null
#  consecutive_empty_listings :integer          default(0), not null
#  consecutive_read_failures  :integer          default(0), not null
#  consecutive_stalls         :integer          default(0), not null
#  last_replica_txid          :integer
#  stalled_since              :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
RSpec.describe ReplicationHeartbeat do
  describe "single-row enforcement" do
    it "refuses a second row while one already exists" do
      described_class.singleton # ensure the singleton row exists

      expect {
        described_class.create!(checked_at: Time.current)
      }.to raise_error(ActiveRecord::RecordInvalid, /one row/i)
    end

    it "allows a create on a genuinely empty table (fresh DB / seed path)" do
      described_class.delete_all

      expect {
        described_class.create!(id: described_class::SINGLETON_ID, checked_at: Time.current)
      }.not_to raise_error
      expect(described_class.count).to eq(1)
    end

    it "refuses a row whose primary key is not 1, even on an empty table" do
      described_class.delete_all

      expect {
        described_class.create!(id: 2, checked_at: Time.current)
      }.to raise_error(ActiveRecord::RecordInvalid, /one row/i)
    end

    # A database check constraint refuses a second row too, one layer below
    # the Ruby-level validation above. insert_all bypasses that validation, so
    # this example checks SQLite's own refusal directly.
    it "is also refused at the database level by the id = 1 check constraint" do
      described_class.singleton

      expect {
        described_class.insert_all([{checked_at: Time.current, created_at: Time.current, updated_at: Time.current}])
      }.to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint failed/i)
    end
  end

  describe ".singleton" do
    it "returns the same row on consecutive calls, and leaves exactly one row behind" do
      first = described_class.singleton
      second = described_class.singleton

      expect(first.id).to eq(second.id)
      expect(described_class.count).to eq(1)
    end
  end
end
