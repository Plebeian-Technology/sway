# frozen_string_literal: true

# @lat: [[legislator-photo-orphan-cleanup#Orphan photo cleanup and merge deletion]]
class LegislatorPhotoPurger
  PHOTO_RECORD_TYPE = "Legislator"
  PHOTO_ATTACHMENT_NAME = "photo"

  class SweepTooLarge < StandardError
  end

  def self.purge_orphans(force: false)
    photo_count_before = photo_attachments.count
    orphan_scope = orphaned_photo_attachments
    orphan_count_before = orphan_scope.count

    if !force && orphan_count_before * 4 > photo_count_before
      raise SweepTooLarge,
        "refusing to purge #{orphan_count_before} of #{photo_count_before} legislator photos; " \
        "pass the explicit force task argument to override the sweep cap"
    end

    purged_count = purge_for_ids(orphan_scope.distinct.pluck(:record_id), owner_state: :missing)

    {
      photo_attachments_before: photo_count_before,
      orphan_photo_attachments_before: orphan_count_before,
      purged_orphan_photo_attachments: purged_count,
      orphan_photo_attachments_after: orphaned_photo_attachments.count
    }
  end

  def self.purge_for_ids(legislator_ids, owner_state:)
    unless %i[missing present].include?(owner_state)
      raise ArgumentError, "owner_state must be :missing or :present"
    end

    count = 0
    photo_attachments.where(record_id: legislator_ids.uniq).find_each do |attachment|
      next unless owner_matches_state?(attachment, owner_state)

      attachment.purge
      count += 1 unless ActiveStorage::Attachment.exists?(attachment.id)
    end

    count
  end

  def self.photo_attachments
    ActiveStorage::Attachment.where(
      record_type: PHOTO_RECORD_TYPE,
      name: PHOTO_ATTACHMENT_NAME
    )
  end

  def self.orphaned_photo_attachments
    photo_attachments.where(<<~SQL.squish)
      NOT EXISTS (
        SELECT 1 FROM legislators
        WHERE legislators.id = active_storage_attachments.record_id
      )
    SQL
  end

  def self.owner_matches_state?(attachment, owner_state)
    case owner_state
    when :missing
      orphaned_photo_attachments.where(id: attachment.id).exists?
    when :present
      connection = ActiveRecord::Base.connection
      connection.select_value(
        "SELECT EXISTS (SELECT 1 FROM legislators WHERE id = #{connection.quote(attachment.record_id)})"
      ) == 1
    end
  end

  private_class_method :photo_attachments, :orphaned_photo_attachments, :owner_matches_state?
end
