# frozen_string_literal: true

# Re-keys the classifier's saved answers by (sway_locale_id, attachment_id).
#
# The UNIQUE index used to cover attachment_id alone. That was correct for
# exactly one reason: Legistar::Client::DEFAULT_CLIENT is "baltimore", so every
# id in the table came from one city. Add a second Legistar jurisdiction and its
# attachment 38947 becomes the SAME ROW as Baltimore's attachment 38947 — one
# bill's testimony answer silently decides another bill's. The matching
# assumption in the sidecar filenames is fixed in the same change
# (Legislation::Paths.attachment_dir); fixing either alone leaves the other able
# to cross jurisdictions on its own.
#
# EXISTING ROWS ARE DELETED, NOT BACKFILLED. This table is a cache and says so:
# every row is re-derivable by classifying the attachment again, and
# TestimonyAttachmentClassification already drops answers whose model or
# prompt_version no longer match, so the system is built to lose them. Deleting
# avoids writing a sway_locale_id nobody measured — the rows carry no
# jurisdiction, so any backfill would be an assumption dressed as data. The cost
# is one re-classification pass: free in development against llama.cpp, and
# irrelevant in production, where this feature is not deployed and the table is
# empty.
class RekeyTestimonyClassificationsBySwayLocale < ActiveRecord::Migration[8.1]
  def up
    # Ordered so the table is never left holding rows that violate the new key:
    # empty it first, then add the NOT NULL column, then the composite index.
    execute("DELETE FROM testimony_attachment_classifications")

    add_reference :testimony_attachment_classifications,
      :sway_locale,
      null: false,
      foreign_key: true,
      index: false

    remove_index :testimony_attachment_classifications,
      name: "index_testimony_classifications_on_attachment_id"

    add_index :testimony_attachment_classifications,
      %i[sway_locale_id attachment_id],
      unique: true,
      name: "index_testimony_classifications_on_locale_and_attachment"
  end

  def down
    remove_index :testimony_attachment_classifications,
      name: "index_testimony_classifications_on_locale_and_attachment"

    remove_reference :testimony_attachment_classifications, :sway_locale, foreign_key: true

    add_index :testimony_attachment_classifications,
      :attachment_id,
      unique: true,
      name: "index_testimony_classifications_on_attachment_id"
  end
end
