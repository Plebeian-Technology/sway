# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "migrate", "20260725000002_key_testimony_classifications_on_attachment_id")

# @lat: [[testimony-classification-migration-dedup-bug#Why attachment_id alone, not (source_endpoint, attachment_id)]]
module TestimonyClassificationMigrationSpecHelpers
  ATTACHMENT_ID_INDEX = "index_testimony_classifications_on_attachment_id"
  ENDPOINT_INDEX = "index_testimony_classifications_on_endpoint_and_attachment"
  # @lat: [[testimony-classification-migration-dedup-bug#Testing against a schema that has already moved on]]
  LOCALE_INDEX = "index_testimony_classifications_on_locale_and_attachment"
end

RSpec.describe "KeyTestimonyClassificationsOnAttachmentId migration", type: :model do
  self.use_transactional_tests = false

  def testimony_classification_index?(name)
    ActiveRecord::Base.connection
      .indexes(:testimony_attachment_classifications)
      .any? { |index| index.name == name }
  end

  # Inserted straight through the database connection. The model checks that
  # attachment_id is unique, and breaking that rule is exactly what this fixture
  # has to do to recreate the pre-migration shape.
  def insert_testimony_classification(id:, attachment_id:, label:, endpoint:, updated_at:)
    stamp = updated_at.utc.iso8601
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO testimony_attachment_classifications
        (id, attachment_id, sway_locale_id, label, source_endpoint, model, created_at, updated_at)
      VALUES
        (#{id}, #{attachment_id}, #{testimony_classification_sway_locale.id}, '#{label}', '#{endpoint}',
         'claude-haiku-5-5', '#{stamp}', '#{stamp}')
    SQL
  end

  # ActiveSupport no longer ships a helper for silencing output streams. The
  # migration's own verbosity flag is the supported way to keep `say` out of the
  # spec output.
  def run_testimony_classification_migration
    was_verbose = ActiveRecord::Migration.verbose
    begin
      ActiveRecord::Migration.verbose = false
      KeyTestimonyClassificationsOnAttachmentId.new.up
    ensure
      ActiveRecord::Migration.verbose = was_verbose
    end
  end

  # @lat: [[testimony-classification-migration-dedup-bug#Why attachment_id alone, not (source_endpoint, attachment_id)]]
  def testimony_classification_sway_locale
    @testimony_classification_sway_locale ||= begin
      attrs = SwayLocale.normalize_attributes(city: "baltimore", state: "maryland", country: "united_states")
      existing = SwayLocale.find_by(**attrs)
      if existing
        existing
      else
        @created_sway_locale = true
        SwayLocale.create!(**attrs)
      end
    end
  end

  # Removes the locale ONLY when this file is what created it. A row that was
  # already there belongs to whoever made it.
  def remove_created_sway_locale
    return unless @created_sway_locale

    @testimony_classification_sway_locale&.destroy
    @created_sway_locale = false
    @testimony_classification_sway_locale = nil
  end

  def surviving_testimony_classifications
    ActiveRecord::Base.connection.select_all(
      "SELECT id, attachment_id, label FROM testimony_attachment_classifications ORDER BY attachment_id, id"
    ).to_a
  end

  before do
    TestimonyAttachmentClassification.delete_all
    # Go back to the pre-migration shape so duplicates can be inserted. BOTH the
    # index this migration created and the one that later replaced it have to
    # come off: whichever is present would refuse the duplicate rows.
    [
      TestimonyClassificationMigrationSpecHelpers::ATTACHMENT_ID_INDEX,
      TestimonyClassificationMigrationSpecHelpers::LOCALE_INDEX
    ].each do |name|
      next unless testimony_classification_index?(name)

      ActiveRecord::Base.connection.remove_index(:testimony_attachment_classifications, name: name)
    end
    unless testimony_classification_index?(TestimonyClassificationMigrationSpecHelpers::ENDPOINT_INDEX)
      ActiveRecord::Base.connection.add_index(
        :testimony_attachment_classifications,
        %i[source_endpoint attachment_id],
        unique: true,
        name: TestimonyClassificationMigrationSpecHelpers::ENDPOINT_INDEX
      )
    end
  end

  # @lat: [[testimony-classification-migration-dedup-bug#Testing against a schema that has already moved on]]
  after do
    TestimonyAttachmentClassification.delete_all
    remove_created_sway_locale
    [
      TestimonyClassificationMigrationSpecHelpers::ENDPOINT_INDEX,
      TestimonyClassificationMigrationSpecHelpers::ATTACHMENT_ID_INDEX
    ].each do |name|
      next unless testimony_classification_index?(name)

      ActiveRecord::Base.connection.remove_index(:testimony_attachment_classifications, name: name)
    end
    unless testimony_classification_index?(TestimonyClassificationMigrationSpecHelpers::LOCALE_INDEX)
      ActiveRecord::Base.connection.add_index(
        :testimony_attachment_classifications,
        %i[sway_locale_id attachment_id],
        unique: true,
        name: TestimonyClassificationMigrationSpecHelpers::LOCALE_INDEX
      )
    end
  end

  # The exact case from the bug report: the corrected verdict sits on the lower
  # id, because the third run updated row 1 in place while the second run had
  # inserted row 2. MAX(id) keeps row 2, the stale not_testimony, and deletes
  # row 1.
  it "keeps the most recently UPDATED verdict, not the most recently inserted row" do
    insert_testimony_classification(id: 1, attachment_id: 38_947, label: "not_testimony",
      endpoint: "event_item_matter_attachments", updated_at: Time.utc(2026, 7, 20, 12, 0, 0))
    insert_testimony_classification(id: 2, attachment_id: 38_947, label: "not_testimony",
      endpoint: "matter_attachments", updated_at: Time.utc(2026, 7, 21, 12, 0, 0))
    # The third run has a better prompt and re-classifies, updating row 1 in place.
    ActiveRecord::Base.connection.execute(
      "UPDATE testimony_attachment_classifications " \
      "SET label = 'testimony', updated_at = '#{Time.utc(2026, 7, 22, 12, 0, 0).iso8601}' WHERE id = 1"
    )

    run_testimony_classification_migration

    rows = surviving_testimony_classifications
    expect(rows.length).to eq(1)
    expect(rows.first["id"]).to eq(1)
    expect(rows.first["label"]).to eq("testimony")
  end

  it "adds the unique attachment_id index and drops the endpoint-scoped one" do
    insert_testimony_classification(id: 10, attachment_id: 5_000, label: "testimony",
      endpoint: "matter_attachments", updated_at: Time.utc(2026, 7, 20))

    run_testimony_classification_migration

    expect(testimony_classification_index?(TestimonyClassificationMigrationSpecHelpers::ATTACHMENT_ID_INDEX)).to be(true)
    expect(testimony_classification_index?(TestimonyClassificationMigrationSpecHelpers::ENDPOINT_INDEX)).to be(false)
  end

  # First tie-break: with nothing to say which row is newer, err on the side of
  # keeping the document. Everywhere else in this subsystem, losing a real
  # position costs more than holding on to one extra document.
  it "prefers the testimony verdict when two rows share an updated_at" do
    same_time = Time.utc(2026, 7, 20, 9, 30, 0)
    insert_testimony_classification(id: 20, attachment_id: 6_000, label: "testimony",
      endpoint: "matter_attachments", updated_at: same_time)
    insert_testimony_classification(id: 21, attachment_id: 6_000, label: "not_testimony",
      endpoint: "event_item_matter_attachments", updated_at: same_time)

    run_testimony_classification_migration

    rows = surviving_testimony_classifications
    expect(rows.length).to eq(1)
    expect(rows.first["label"]).to eq("testimony")
  end

  it "leaves distinct attachments untouched" do
    insert_testimony_classification(id: 30, attachment_id: 7_000, label: "testimony",
      endpoint: "matter_attachments", updated_at: Time.utc(2026, 7, 20))
    insert_testimony_classification(id: 31, attachment_id: 7_001, label: "not_testimony",
      endpoint: "matter_attachments", updated_at: Time.utc(2026, 7, 20))

    run_testimony_classification_migration

    expect(surviving_testimony_classifications.pluck("attachment_id")).to eq([7_000, 7_001])
  end
end
