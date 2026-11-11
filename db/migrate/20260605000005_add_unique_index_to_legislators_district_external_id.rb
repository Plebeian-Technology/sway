# frozen_string_literal: true

# Phase 65 (R1/R2): reworked in place — prod has not run past schema_migrations
# 20260603140733, so this undeployed migration is edited rather than
# superseded (RESEARCH "Migration Chain to Edit"). Formerly added
# UNIQUE(district_id, external_id) on legislators — that target is invalid
# post-remodel: identity moves to (sway_locale_id, external_id) on
# `legislators` (person-level), and `legislator_terms` (not `legislators`)
# now carries `district_id` per term.
#
# `legislator_terms`' own UNIQUE(legislator_id, term_start_year) index is
# already added by 20260605000003_create_legislator_terms.rb (Task 2, step
# 3) — there is nothing left for THIS migration to add at that grain.
#
# The target UNIQUE(sway_locale_id, external_id) index on `legislators`
# CANNOT be added here: sway_locale_id is still NULL pre-backfill (see
# 20260605000001) until the 65-10 data migration converts the 180 duplicate
# (locale, external_id) groups into legislator_terms rows. That finalize
# migration (65-10) is where this index — and the defensive duplicate-check
# `raise` idiom below, preserved verbatim for reuse — belongs:
#
#   dupes = Legislator.group(:sway_locale_id, :external_id).having("COUNT(*) > 1").count
#   if dupes.any?
#     offenders = dupes.map { |(locale_id, ext_id), cnt|
#       "(sway_locale_id=#{locale_id}, external_id=#{ext_id.inspect}, count=#{cnt})"
#     }.join(", ")
#     raise <<~MSG.squish
#       AddUniqueIndexToLegislatorsSwayLocaleExternalId: cannot add unique index —
#       #{dupes.size} duplicate (sway_locale_id, external_id) pair(s) found: #{offenders}.
#       Run the 65-10 data migration first.
#     MSG
#   end
#   add_index :legislators, [:sway_locale_id, :external_id], unique: true
#
# This migration is therefore a documented no-op in this plan.
class AddUniqueIndexToLegislatorsDistrictExternalId < ActiveRecord::Migration[8.1]
  def change
  end
end
