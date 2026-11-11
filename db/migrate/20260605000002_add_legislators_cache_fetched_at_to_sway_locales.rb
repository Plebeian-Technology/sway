# frozen_string_literal: true

# Adds legislators_cache_fetched_at to sway_locales.
# Nullable — nil means "never fetched". Set by the per-locale refreshers
# (Plans 03-05) after each successful legislators.json regeneration.
class AddLegislatorsCacheFetchedAtToSwayLocales < ActiveRecord::Migration[8.1]
  def change
    add_column :sway_locales, :legislators_cache_fetched_at, :datetime
  end
end
