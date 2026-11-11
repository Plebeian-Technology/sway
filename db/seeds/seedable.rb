# frozen_string_literal: true

# @lat: [[seedable-module#seed_or_skip? decision table]]
module Seedable
  def seed_or_skip?(record, force: false)
    return false if record.new_record?
    return false if force
    return false if record.last_seeded_at.nil?

    record.updated_at != record.last_seeded_at
  end

  def stamp_seeded_at!(record)
    record.update_columns(last_seeded_at: record.updated_at)
    # @lat: [[seedable-module#When to call stamp_seeded_at!]]
    record.reload
  end
end
