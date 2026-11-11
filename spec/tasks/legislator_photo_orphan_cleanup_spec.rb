# frozen_string_literal: true

require "rails_helper"
require "rake"
require Rails.root.join("db", "data", "20260812000001_join_baltimore_council_rows_to_one_person")

module LegislatorPhotoCleanupSpecHelpers
  def attach_cleanup_photo(legislator)
    legislator.photo.attach(
      io: StringIO.new("portrait bytes for #{legislator.external_id}"),
      filename: "#{legislator.external_id}.jpg",
      content_type: "image/jpeg"
    )
    attachment = ActiveStorage::Attachment.find_by!(record: legislator, name: "photo")
    @photo_keys << attachment.blob.key
    attachment.blob
  end
end

RSpec.describe "Legislator photo orphan cleanup" do
  include LegislatorPhotoCleanupSpecHelpers

  let(:task) { Rake::Task["sway:assets:purge_orphaned_legislator_photos"] }

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:assets:purge_orphaned_legislator_photos")
  end

  before do
    @photo_keys = []
  end

  after do
    storage = ActiveStorage::Blob.service
    @photo_keys.uniq.each { |key| storage.delete(key) if storage.exist?(key) }
  end

  # @lat: [[legislator-photo-orphan-cleanup#Orphan photo cleanup and merge deletion]]
  it "purges orphan photos while preserving live and shared photo blobs" do
    task.reenable

    orphan = create(:legislator)
    orphan_blob = attach_cleanup_photo(orphan)
    orphan_attachment_id = orphan.photo.attachment.id
    Legislator.where(id: orphan.id).delete_all

    keeper = create(:legislator)
    keeper_blob = attach_cleanup_photo(keeper)
    keeper_attachment_id = keeper.photo.attachment.id
    shared_orphan = create(:legislator)
    shared_orphan.photo.attach(keeper_blob)
    shared_orphan_attachment_id = shared_orphan.photo.attachment.id
    @photo_keys << keeper_blob.key
    Legislator.where(id: shared_orphan.id).delete_all

    expect(orphan_blob.service.exist?(orphan_blob.key)).to be(true)
    expect(keeper_blob.service.exist?(keeper_blob.key)).to be(true)

    organization = create(:organization)
    organization.icon.attach(
      io: StringIO.new("organization icon bytes"),
      filename: "organization-icon.png",
      content_type: "image/png"
    )
    organization_icon_attachment_id = organization.icon.attachment.id
    @photo_keys << organization.icon.blob.key
    keeper_non_photo_attachment = ActiveStorage::Attachment.create!(
      name: "avatar",
      record: keeper,
      blob: keeper_blob
    )

    output = StringIO.new
    previous_stdout = $stdout
    begin
      $stdout = output
      task.invoke("force")
    ensure
      $stdout = previous_stdout
    end

    expect(ActiveStorage::Attachment.exists?(keeper_attachment_id)).to be(true)
    expect(ActiveStorage::Blob.exists?(keeper_blob.id)).to be(true)
    expect(keeper_blob.service.exist?(keeper_blob.key)).to be(true)

    expect(ActiveStorage::Attachment.exists?(orphan_attachment_id)).to be(false)
    expect(ActiveStorage::Blob.exists?(orphan_blob.id)).to be(false)
    expect(orphan_blob.service.exist?(orphan_blob.key)).to be(false)

    expect(ActiveStorage::Attachment.exists?(shared_orphan_attachment_id)).to be(false)
    expect(ActiveStorage::Blob.exists?(keeper_blob.id)).to be(true)
    expect(keeper.reload.photo.blob.id).to eq(keeper_blob.id)
    expect(keeper_blob.service.exist?(keeper_blob.key)).to be(true)
    expect(ActiveStorage::Attachment.exists?(organization_icon_attachment_id)).to be(true)
    expect(ActiveStorage::Attachment.exists?(keeper_non_photo_attachment.id)).to be(true)
    expect(output.string).to match(/purged 2 orphan legislator photos/)

    task.reenable
    expect { task.invoke("force") }.to output(/purged 0 orphan legislator photos/).to_stdout
  end

  it "refuses a default run when orphan photos exceed one quarter of Legislator photos" do
    orphaned = create_list(:legislator, 2)
    orphaned.each do |legislator|
      attach_cleanup_photo(legislator)
      Legislator.where(id: legislator.id).delete_all
    end
    live = create(:legislator)
    live_blob = attach_cleanup_photo(live)
    live_attachment_id = live.photo.attachment.id
    task.reenable

    expect { task.invoke }.to raise_error(LegislatorPhotoPurger::SweepTooLarge)

    expect(ActiveStorage::Attachment.where(record_type: "Legislator", name: "photo").count).to eq(3)
    expect(ActiveStorage::Attachment.exists?(live_attachment_id)).to be(true)
    expect(live_blob.service.exist?(live_blob.key)).to be(true)
  end

  it "does nothing on an empty photo inventory" do
    task.reenable

    expect { task.invoke }.to output(/purged 0 orphan legislator photos/).to_stdout
  end

  it "keeps a live photo when the helper is asked to purge a missing owner" do
    legislator = create(:legislator)
    blob = attach_cleanup_photo(legislator)
    attachment_id = legislator.photo.attachment.id

    expect(
      LegislatorPhotoPurger.purge_for_ids([legislator.id], owner_state: :missing)
    ).to eq(0)

    expect(ActiveStorage::Attachment.exists?(attachment_id)).to be(true)
    expect(blob.service.exist?(blob.key)).to be(true)
  end

  it "purges a retiring photo before the real callback-free merge deletes that row" do
    locale = create(:sway_locale, :baltimore)
    retiring = create(
      :legislator,
      sway_locale: locale,
      external_id: "brandon-scott-2020",
      first_name: "Brandon",
      last_name: "Scott"
    )
    keeper = create(
      :legislator,
      sway_locale: locale,
      external_id: "baltimore-mayor|brandon-scott",
      first_name: "Brandon",
      last_name: "Scott"
    )
    retiring_blob = attach_cleanup_photo(retiring)
    keeper_blob = attach_cleanup_photo(keeper)
    retiring_attachment_id = retiring.photo.attachment.id
    keeper_attachment_id = keeper.photo.attachment.id

    JoinBaltimoreCouncilRowsToOnePerson.new.up

    expect(Legislator.exists?(retiring.id)).to be(false)
    expect(ActiveStorage::Attachment.exists?(retiring_attachment_id)).to be(false)
    expect(retiring_blob.service.exist?(retiring_blob.key)).to be(false)
    expect(Legislator.find(keeper.id).external_id).to eq("baltimore-mayor|brandon-scott")
    expect(ActiveStorage::Attachment.exists?(keeper_attachment_id)).to be(true)
    expect(keeper.reload.photo.blob.id).to eq(keeper_blob.id)
    expect(keeper_blob.service.exist?(keeper_blob.key)).to be(true)
  end

  it "keeps a shared keeper blob when the merge retires another attachment to it" do
    locale = create(:sway_locale, :baltimore)
    retiring = create(
      :legislator,
      sway_locale: locale,
      external_id: "antonio-glover-2020",
      first_name: "Antonio",
      last_name: "Glover"
    )
    keeper = create(
      :legislator,
      sway_locale: locale,
      external_id: "baltimore-district-13|antonio-glover",
      first_name: "Antonio",
      last_name: "Glover"
    )
    keeper_blob = attach_cleanup_photo(keeper)
    retiring.photo.attach(keeper_blob)
    @photo_keys << keeper_blob.key
    retiring_attachment_id = retiring.photo.attachment.id
    keeper_attachment_id = keeper.photo.attachment.id

    JoinBaltimoreCouncilRowsToOnePerson.new.up

    expect(Legislator.exists?(retiring.id)).to be(false)
    expect(ActiveStorage::Attachment.exists?(retiring_attachment_id)).to be(false)
    expect(ActiveStorage::Attachment.exists?(keeper_attachment_id)).to be(true)
    expect(ActiveStorage::Blob.exists?(keeper_blob.id)).to be(true)
    expect(keeper.reload.photo.blob.id).to eq(keeper_blob.id)
    expect(keeper_blob.service.exist?(keeper_blob.key)).to be(true)
  end
end
