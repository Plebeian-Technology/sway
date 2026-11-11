# frozen_string_literal: true

# Converts duplicate (sway_locale, external_id) Congress legislator groups
# and the McCormick M001218 GA6->GA7 redistricting pair into first-class legislator_terms rows on ONE canonical
# person per identity — replacing the superseded, now-deleted
# db/migrate/20260604000001, which merged duplicates down and DISCARDED
# their term history.
#
# Reference pattern (20260604000001, read from git history): the repoint-FK
# logic (legislator_votes -> canonical, user_legislators dedupe-or-repoint,
# bills sponsor repoint, bill_cosponsors dedupe-or-repoint) is reused
# verbatim. The ONLY change: a "loser" row's physical existence (title,
# district, vintage) becomes a legislator_terms row on the canonical person
# instead of being discarded, and every score row that pointed at a loser
# is re-derived onto that term instead of deleted.
#
# Every row this migration touches — winner AND loser alike — gets exactly
# one legislator_terms row (not just duplicates): a lone, never-duplicated
# legislator also predates the term-table design and has never had one.
#
# Runs strictly BEFORE db/migrate/20260711000010/11 (the finalize
# migrations), which drop the legacy legislators.district_id/active/title
# columns and the user_legislator_scores table this migration still reads —
# timestamp ordering is load-bearing. Because 20260711000010/11 land in the
# SAME deploy, the app-level UserLegislatorScore
# model/table will already be gone from the CODEBASE by the time this
# migration file is read for a real deploy; a private in-migration
# ActiveRecord class (LegacyUserLegislatorScore, below) reads that table
# directly rather than depending on the (about-to-be-deleted) app model.
#
class ConvertDuplicateLegislatorsToTerms < ActiveRecord::Migration[8.1]
  # user_legislator_scores is dropped by 20260711000011 (same deploy) — a
  # private, table-name-only AR class avoids depending on the app's
  # UserLegislatorScore model, which is deleted from the codebase.
  class LegacyUserLegislatorScore < ActiveRecord::Base
    self.table_name = "user_legislator_scores"
  end

  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"
    alias_attribute :state, :region_name if column_names.include?("region_name")

    def congress?
      city_name == "congress" && region_name == "congress"
    end

    def regional?
      return false if congress?

      RegionUtil.from_region_name_to_region_code(city_name).present? &&
        RegionUtil.from_region_name_to_region_code(city_name) ==
          RegionUtil.from_region_name_to_region_code(region_name)
    end

    # @lat: [[migrations-name-no-model#The calculators a stand-in cannot replace]]
    def term_rules
      SwayLocale::TermRulesRegistry.fetch(name)
    end

    def declared_term_rules?
      SwayLocale::TermRulesRegistry.declared?(name)
    end

    def name
      "#{city_name}-#{region_name}-#{country_name}"
    end

    def city_name
      format_name(city)
    end

    def region_name
      format_name(RegionUtil.from_region_code_to_region_name(state))
    end

    def country_name
      format_name(RegionUtil.from_country_code_to_name(country))
    end

    private

    def format_name(value)
      value.to_s.strip.downcase.split(" ").join("_")
    end
  end

  class MigrationDistrict < ActiveRecord::Base
    self.table_name = "districts"

    belongs_to :sway_locale,
      class_name: "ConvertDuplicateLegislatorsToTerms::MigrationSwayLocale",
      optional: true
  end

  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"
  end

  class MigrationLegislatorTerm < ActiveRecord::Base
    self.table_name = "legislator_terms"

    belongs_to :legislator,
      class_name: "ConvertDuplicateLegislatorsToTerms::MigrationLegislator",
      optional: true
    belongs_to :district,
      class_name: "ConvertDuplicateLegislatorsToTerms::MigrationDistrict",
      optional: true

    def sway_locale
      district&.sway_locale
    end
  end

  class MigrationLegislatorVote < ActiveRecord::Base
    self.table_name = "legislator_votes"
  end

  class MigrationUserLegislator < ActiveRecord::Base
    self.table_name = "user_legislators"
  end

  class MigrationUserLegislatorEmail < ActiveRecord::Base
    self.table_name = "user_legislator_emails"
  end

  class MigrationUserLegislatorTermScore < ActiveRecord::Base
    self.table_name = "user_legislator_term_scores"
  end

  class MigrationLegislatorDistrictScore < ActiveRecord::Base
    self.table_name = "legislator_district_scores"
  end

  class MigrationLegislatorLocaleScore < ActiveRecord::Base
    self.table_name = "legislator_locale_scores"
  end

  class MigrationBill < ActiveRecord::Base
    self.table_name = "bills"
  end

  class MigrationBillCosponsor < ActiveRecord::Base
    self.table_name = "bill_cosponsors"
  end

  class MigrationUserDistrict < ActiveRecord::Base
    self.table_name = "user_districts"
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#A term carries the day it really began]]
  CandidateTermYear = Struct.new(:term_start_year, :sway_locale, :began_on)

  def up
    # @lat: [[migrations-name-no-model#Why a stand-in re-reads its columns]]
    [
      MigrationLegislator, MigrationDistrict, MigrationLegislatorTerm,
      MigrationLegislatorVote, MigrationUserLegislator,
      MigrationUserLegislatorEmail, MigrationUserLegislatorTermScore,
      MigrationLegislatorDistrictScore, MigrationLegislatorLocaleScore,
      MigrationBill, MigrationBillCosponsor, MigrationUserDistrict,
      LegacyUserLegislatorScore
    ].each(&:reset_column_information)

    # old legislators.id => the legislator_terms.id created FROM that row.
    term_id_for_legislator_id = {}
    # old legislators.id => the canonical (surviving) legislators.id for its
    # group. Used to keep legislator_{district,locale}_scores.legislator_id
    # (still a live FK until the finalize migration) pointed at a row that
    # will still exist once losers are deleted.
    canonical_id_for_legislator_id = {}
    loser_ids_to_delete = []
    # The set of user_legislators.id values whose
    # legacy user_legislator_scores row has ALREADY been migrated (as a
    # loser-linked SOURCE inside repoint_user_legislators below). Every
    # OTHER UserLegislator — one linked to a never-duplicated legislator, or
    # one already linked directly to a group's canonical (winning) row — is
    # never touched by that loser-scoped loop, so its own legacy score would
    # otherwise be silently abandoned before 20260711000011 drops the source
    # table. Tracking this set also guarantees
    # migrate_remaining_user_legislator_scores! below visits each SOURCE
    # user_legislator_id at most once across this whole run, so the
    # additive merge in migrate_user_legislator_score! cannot double-count.
    migrated_user_legislator_source_ids = Set.new

    district_by_id = MigrationDistrict.includes(:sway_locale).index_by(&:id)
    groups = MigrationLegislator.all.to_a.group_by { |l| [district_by_id[l.district_id]&.sway_locale_id, l.external_id] }

    groups.each_value do |rows|
      sway_locale = district_by_id[rows.first.district_id]&.sway_locale
      next if sway_locale.nil? # defensive: an orphaned district_id — nothing to convert

      canonical = pick_canonical(rows)
      canonical.update_columns(sway_locale_id: sway_locale.id)

      rows.each do |row|
        term_id_for_legislator_id[row.id] = term_id_for(canonical, row, district_by_id[row.district_id], sway_locale)
        canonical_id_for_legislator_id[row.id] = canonical.id
      end

      losers = rows - [canonical]
      next if losers.empty?

      loser_ids = losers.map(&:id)
      repoint_legislator_votes(loser_ids, canonical.id)
      repoint_user_legislators(loser_ids, canonical.id, term_id_for_legislator_id, migrated_user_legislator_source_ids)
      repoint_bills_sponsor(loser_ids, canonical.id)
      repoint_bill_cosponsors(loser_ids, canonical.id)

      loser_ids_to_delete.concat(loser_ids)
    end

    repoint_legislator_scores(term_id_for_legislator_id, canonical_id_for_legislator_id)
    migrate_remaining_user_legislator_scores!(term_id_for_legislator_id, migrated_user_legislator_source_ids)
    backfill_user_districts

    # @lat: [[legislator-photo-orphan-cleanup#Orphan photo cleanup and merge deletion]]
    LegislatorPhotoPurger.purge_for_ids(loser_ids_to_delete, owner_state: :present) if loser_ids_to_delete.any?
    MigrationLegislator.where(id: loser_ids_to_delete).delete_all if loser_ids_to_delete.any?
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Canonical = the row the last seed refresh considered current (mirrors
  # the superseded migration's tie-break): active DESC, updated_at DESC,
  # id DESC.
  def pick_canonical(rows)
    rows.max_by { |l| [l.active ? 1 : 0, l.updated_at, l.id] }
  end

  # One legislator_terms row per PHYSICAL row consumed — vintage
  # (last_seeded_at || created_at) buckets into the term-year window it
  # falls in, via the SAME TermWindow choke point every other vote/score
  # consumer uses (never re-derived ad hoc).
  # find_or_create_by! so two rows that vintage into the SAME term (the
  # common duplicate-group case — a re-seeded, unchanged row) converge
  # on one term instead of colliding on legislator_terms'
  # UNIQUE(legislator_id, term_start_year).
  def term_id_for(canonical, row, district, sway_locale)
    vintage = row.last_seeded_at || row.created_at
    term_start_year = term_start_year_for(sway_locale, vintage)

    term =
      MigrationLegislatorTerm.find_or_create_by!(legislator: canonical, term_start_year: term_start_year) do |t|
        t.district_id = district&.id || row.district_id
        t.term_end_year = term_start_year + (sway_locale.congress? ? 2 : 4)
        t.title = row.title
      end

    term.id
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#A term carries the day it really began]]
  def term_start_year_for(sway_locale, vintage)
    candidates = candidate_term_start_years(sway_locale).map { |year| CandidateTermYear.new(year, sway_locale) }
    winner = TermWindow.covering(vintage.to_date, candidates)
    return winner.term_start_year if winner

    candidates.min_by { |c| TermWindow.convening_date(c.sway_locale, c.term_start_year) }.term_start_year
  end

  # A broad, deterministic sweep of every plausible term-start year for this
  # locale's cycle (Congress: 2yr/odd years; Maryland/Baltimore: 4yr from
  # their TermWindow anchor) — wide enough to cover any real production
  # vintage without hard-coding specific years.
  def candidate_term_start_years(sway_locale)
    if sway_locale.congress?
      (1991..2051).step(2).to_a
    elsif sway_locale.regional?
      anchor_sweep(2023)
    else
      anchor_sweep(2024)
    end
  end

  def anchor_sweep(anchor)
    ((anchor - 32)..(anchor + 28)).step(4).to_a
  end

  # UNIQUE(bill_id, legislator_id) — a repoint that would collide with a
  # vote the canonical row already has is a same-bill double-vote artifact
  # from the duplicate identity; drop the loser's redundant row
  # (same-person, same-bill fact — no identity lost) rather than raise.
  def repoint_legislator_votes(loser_ids, canonical_id)
    MigrationLegislatorVote
      .where(legislator_id: loser_ids)
      .where(bill_id: MigrationLegislatorVote.where(legislator_id: canonical_id).select(:bill_id))
      .delete_all

    MigrationLegislatorVote.where(legislator_id: loser_ids).update_all(legislator_id: canonical_id)
  end

  # UNIQUE(user_id, legislator_id) — where the user is already linked to the
  # canonical row, the loser link is redundant. Its user_legislator_score is
  # migrated onto the SURVIVING link (as a term-scoped row) before the
  # redundant row + its legacy score/email rows are dropped; otherwise the
  # loser row is simply repointed in place.
  def repoint_user_legislators(loser_ids, canonical_id, term_id_for_legislator_id, migrated_source_ids)
    MigrationUserLegislator.where(legislator_id: loser_ids).find_each do |ul|
      old_legislator_id = ul.legislator_id
      term_id = term_id_for_legislator_id[old_legislator_id]
      duplicate = MigrationUserLegislator.find_by(user_id: ul.user_id, legislator_id: canonical_id)
      surviving_id = duplicate&.id || ul.id

      migrate_user_legislator_score!(ul.id, surviving_id, term_id)
      migrated_source_ids << ul.id # this SOURCE is covered — never re-visited by the sweep below

      if duplicate
        MigrationUserLegislatorEmail.where(user_legislator_id: ul.id).delete_all
        LegacyUserLegislatorScore.where(user_legislator_id: ul.id).delete_all
        MigrationUserLegislator.where(id: ul.id).delete_all
      else
        ul.update_columns(legislator_id: canonical_id)
      end
    end
  end

  # repoint_user_legislators only migrates the legacy score for
  # UserLegislator rows that were linked to a LOSING duplicate row (the
  # `source` argument there is always a loser's own id). Two classes of
  # surviving UserLegislator are never visited by that loop, and would
  # otherwise have their legacy score silently abandoned before
  # 20260711000011 drops user_legislator_scores:
  #   1. a link to a legislator that was NEVER part of a duplicate group
  #      (the overwhelming majority);
  #   2. a link already pointed directly at a group's CANONICAL (winning)
  #      row — repoint_user_legislators only ever reads/writes the LOSER
  #      side of a collision, never the survivor's own pre-existing score.
  # Every remaining UserLegislator (after the group loop + deletions above,
  # every row's legislator_id is already canonical) that was NOT already
  # covered as a migration SOURCE gets its own legacy score migrated here,
  # onto the term its OWN legislator row's vintage falls into.
  def migrate_remaining_user_legislator_scores!(term_id_for_legislator_id, migrated_source_ids)
    MigrationUserLegislator.where.not(id: migrated_source_ids.to_a).find_each do |ul|
      migrate_user_legislator_score!(ul.id, ul.id, term_id_for_legislator_id[ul.legislator_id])
    end
  end

  # find_or_create_by!'s block only runs on CREATE — if two DIFFERENT
  # sources land on the same (target, term) slot (the exact scenario this
  # migration exists to fix: one user independently linked to two losing
  # rows of the SAME duplicate group), a plain find_or_create_by! silently
  # drops every source after the first. Merge additively instead. This is
  # safe from double-counting WITHIN one execution of #up because every
  # caller (repoint_user_legislators' loop + the sweep above) visits each
  # SOURCE user_legislator_id at MOST ONCE — tracked via
  # migrated_user_legislator_source_ids — so this method is never invoked
  # twice for the same source in a single run. (A re-run of this migration
  # after a partial failure is a separate, pre-existing risk: the migration
  # is a one-time, non-idempotent data conversion, consistent with every
  # other destructive step it performs — see the class doc comment.)
  def migrate_user_legislator_score!(source_user_legislator_id, target_user_legislator_id, term_id)
    return if term_id.nil?

    score = LegacyUserLegislatorScore.find_by(user_legislator_id: source_user_legislator_id)
    return if score.nil?
    return if [score.count_agreed, score.count_disagreed, score.count_no_legislator_vote, score.count_legislator_abstained].sum.zero?

    row = MigrationUserLegislatorTermScore.find_or_create_by!(
      user_legislator_id: target_user_legislator_id, legislator_term_id: term_id
    )
    row.update!(
      count_agreed: row.count_agreed + score.count_agreed,
      count_disagreed: row.count_disagreed + score.count_disagreed,
      count_no_legislator_vote: row.count_no_legislator_vote + score.count_no_legislator_vote,
      count_legislator_abstained: row.count_legislator_abstained + score.count_legislator_abstained
    )
  end

  # Sponsorships follow the person.
  def repoint_bills_sponsor(loser_ids, canonical_id)
    MigrationBill.where(legislator_id: loser_ids).update_all(legislator_id: canonical_id)
  end

  # No compound unique index on bill_cosponsors, but a (bill, canonical)
  # pair that would become a duplicate cosponsorship is still dropped
  # defensively (same person, same bill — no identity lost), mirroring the
  # legislator_votes repoint above.
  def repoint_bill_cosponsors(loser_ids, canonical_id)
    MigrationBillCosponsor
      .where(legislator_id: loser_ids)
      .where(bill_id: MigrationBillCosponsor.where(legislator_id: canonical_id).select(:bill_id))
      .delete_all

    MigrationBillCosponsor.where(legislator_id: loser_ids).update_all(legislator_id: canonical_id)
  end

  # Re-derives every legislator-side aggregate score row onto the term it
  # covered (the score FACT per term is never discarded) — legislator_id is kept pointed at the
  # still-existing canonical row rather than nulled, so no dangling FK survives
  # once losers are deleted below.
  #
  # Rows CONVERGING on the same term (two re-seeded vintages of the same
  # seat, e.g. the Jan+Aug-2025 pair -> one 119th term) each carry their own
  # aggregate row, but only one can hold UNIQUE(legislator_term_id): these
  # are superseded snapshots of the SAME recomputed absolute aggregate (same
  # rationale as 20260602145721), so the freshest (updated_at, then id) wins
  # the term slot and the stale duplicates are dropped — the term-scoped
  # score identity itself is preserved exactly once.
  def repoint_legislator_scores(term_id_for_legislator_id, canonical_id_for_legislator_id)
    legislator_ids_by_term_id = Hash.new { |hash, key| hash[key] = [] }
    term_id_for_legislator_id.each { |legislator_id, term_id| legislator_ids_by_term_id[term_id] << legislator_id }

    legislator_ids_by_term_id.each do |term_id, old_legislator_ids|
      canonical_id = canonical_id_for_legislator_id.fetch(old_legislator_ids.first)

      [MigrationLegislatorDistrictScore, MigrationLegislatorLocaleScore].each do |klass|
        rows =
          klass
            .where(legislator_id: old_legislator_ids, legislator_term_id: nil)
            .order(updated_at: :desc, id: :desc)
            .to_a

        # Defensive: a row already keyed to this term (should not exist
        # pre-conversion) makes every unkeyed candidate a stale duplicate.
        rows.unshift(nil) if klass.where(legislator_term_id: term_id).exists?

        winner = rows.shift
        winner&.update_columns(legislator_term_id: term_id, legislator_id: canonical_id)
        klass.where(id: rows.compact.map(&:id)).delete_all if rows.any?
      end
    end
  end

  # The stored, diffable fact of every district a user is
  # currently assigned to, derived offline from active user_legislators ->
  # legislator -> (freshly-created-above) active term -> district.
  def backfill_user_districts
    now = Time.current

    links = MigrationUserLegislator.where(active: true).to_a
    terms_by_legislator_id =
      MigrationLegislatorTerm
        .where(legislator_id: links.map(&:legislator_id).uniq)
        .includes(district: :sway_locale)
        .group_by(&:legislator_id)

    rows =
      links
        .filter_map do |ul|
          term = running_term(terms_by_legislator_id[ul.legislator_id] || [])
          district_id = term&.district_id
          next if district_id.nil?

          {user_id: ul.user_id, district_id: district_id, active: true, created_at: now, updated_at: now}
        end
        .uniq { |row| [row[:user_id], row[:district_id]] }

    MigrationUserDistrict.insert_all(rows) if rows.any?
  end

  # @lat: [[migrations-name-no-model#The calculators a stand-in cannot replace]]
  def running_term(terms)
    answerable = terms.select { |term| term.sway_locale&.declared_term_rules? }
    TermWindow.running_on(Date.current, answerable)
  end
end
