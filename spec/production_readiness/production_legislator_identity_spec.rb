# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislator-identity-value-design#What production_legislator_identity_spec.rb checks]]
RSpec.describe "Production snapshot legislator identity", :production_snapshot, type: :model do
  include_context "production snapshot (migrated)"

  it "holds one row in office per person, in every locale" do
    duplicates =
      Legislator
        .serving
        .group_by { |legislator| [legislator.sway_locale_id, legislator.full_name.downcase] }
        .select { |_, rows| rows.size > 1 }
        .map { |(locale_id, name), rows| "locale #{locale_id} #{name}: #{rows.map(&:external_id).join(", ")}" }

    expect(duplicates).to be_empty,
      "the same person is in office under more than one row:\n  #{duplicates.join("\n  ")}"
  end

  it "never lists the same person twice on a reader's legislators page" do
    repeated =
      User.find_each.flat_map { |user|
        user
          .user_legislators
          .joins(legislator: :active_term)
          .where(active: true)
          .group_by { |link| [link.legislator.sway_locale_id, link.legislator.full_name.downcase] }
          .select { |_, links| links.size > 1 }
          .map { |(locale_id, name), links| "user #{user.id}, locale #{locale_id}: #{name} listed #{links.size} times" }
      }

    expect(repeated).to be_empty,
      "readers see the same representative more than once:\n  #{repeated.join("\n  ")}"
  end
end
