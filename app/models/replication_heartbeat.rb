# frozen_string_literal: true

# @lat: [[replication-lag-check-job-design#ReplicationHeartbeat holds exactly one row]]
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
class ReplicationHeartbeat < ApplicationRecord
  SINGLETON_ID = 1

  # @lat: [[replication-lag-check-job-design#ReplicationHeartbeat holds exactly one row]]
  validate :enforce_single_row

  # @lat: [[replication-lag-check-job-design#ReplicationHeartbeat holds exactly one row]]
  def self.singleton
    find_or_create_by!(id: SINGLETON_ID) { |record| record.checked_at = Time.zone.now }
  end

  private

  def enforce_single_row
    return unless new_record?

    if id.present? && id != SINGLETON_ID
      errors.add(:base, "ReplicationHeartbeat holds exactly one row, at id #{SINGLETON_ID} — refusing id #{id}.")
      return
    end

    return unless self.class.exists?

    errors.add(:base, "ReplicationHeartbeat holds exactly one row — there is already one.")
  end
end
