# frozen_string_literal: true

require "rails_helper"

# @lat: [[organizations-controller-notes#What production_organization_icon_sources_spec.rb checks]]
RSpec.describe "Production snapshot organization icon sources", :production_snapshot, type: :model do
  include_context "production snapshot (migrated)"

  it "never records our own storage as where a picture came from" do
    ours =
      Organization
        .where("icon_url LIKE ?", "%/rails/active_storage/%")
        .pluck(:id, :name, :icon_url)
        .map { |id, name, url| "#{id} #{name}: #{url}" }

    expect(ours).to be_empty,
      "these record our own address as the picture's source:\n  #{ours.join("\n  ")}"
  end
end
