# frozen_string_literal: true

# Re-keys the stage-3 verdict cache on attachment_id ALONE, replacing
# 20260725000001's (source_endpoint, attachment_id) key.
#
# @lat: [[testimony-classification-migration-dedup-bug#Why attachment_id alone, not (source_endpoint, attachment_id)]]
class KeyTestimonyClassificationsOnAttachmentId < ActiveRecord::Migration[8.1]
  def up
    collapse_duplicate_attachment_ids!

    remove_index :testimony_attachment_classifications,
      name: "index_testimony_classifications_on_endpoint_and_attachment"
    add_index :testimony_attachment_classifications,
      :attachment_id,
      unique: true,
      name: "index_testimony_classifications_on_attachment_id"
  end

  # NOT data-reversible. The schema reverts cleanly and `rails db:rollback`
  # reports success, but the rows collapse_duplicate_attachment_ids! deleted
  # are gone for good. Standard for a dedupe migration — noted here so the
  # presence of a `down` does not mislead the next reader.
  def down
    remove_index :testimony_attachment_classifications,
      name: "index_testimony_classifications_on_attachment_id"
    add_index :testimony_attachment_classifications,
      %i[source_endpoint attachment_id],
      unique: true,
      name: "index_testimony_classifications_on_endpoint_and_attachment"
  end

  private

  # A dev database that ran the old scheme can hold two rows per attachment,
  # one per endpoint — verdicts on the SAME document. The unique index
  # cannot be added until they collapse to one row per attachment_id.
  #
  # Ordered by updated_at DESC, not MAX(id).
  #
  # @lat: [[testimony-classification-migration-dedup-bug#Why attachment_id alone, not (source_endpoint, attachment_id)]]
  def collapse_duplicate_attachment_ids!
    before_count = select_value("SELECT COUNT(*) FROM testimony_attachment_classifications").to_i

    execute(<<~SQL.squish)
      DELETE FROM testimony_attachment_classifications
      WHERE id NOT IN (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (
            PARTITION BY attachment_id
            ORDER BY updated_at DESC,
                     CASE label WHEN 'testimony' THEN 0 ELSE 1 END,
                     id DESC
          ) AS rn
          FROM testimony_attachment_classifications
        ) WHERE rn = 1
      )
    SQL

    after_count = select_value("SELECT COUNT(*) FROM testimony_attachment_classifications").to_i
    collapsed = before_count - after_count
    # Visible in the migration output so an operator can see it happened at
    # all — a silent delete of cached verdicts is exactly what made the
    # MAX(id) ordering hard to notice.
    say("collapsed #{collapsed} duplicate testimony classification row(s)") if collapsed.positive?
  end
end
