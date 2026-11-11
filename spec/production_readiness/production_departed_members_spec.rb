# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "legislator")
require Rails.root.join("db", "seeds", "models", "sway_locale")

# @lat: [[seed-legislator-terms-add-correct-retire#What production_departed_members_spec.rb verifies]]
RSpec.describe "Production snapshot departed members of Congress", :production_snapshot, type: :model do
  include_context "production snapshot (migrated)"

  let(:congress) do
    SwayLocale.find_by!(city: "congress", state: "congress", country: "united_states")
  end

  let(:roster_entries) do
    JSON.parse(
      Rails.root.join("db", "seeds", "data", "united_states", "congress", "congress", "legislators.json").read
    )
  end

  # Everyone the roster names but no longer calls a current member.
  let(:departed_entries) do
    roster_entries.select { |entry| entry["currentMember"] == false }
  end

  def seed_congress!
    SeedLegislator.run([congress], force: true)
  end

  def stored_spans(external_id)
    Legislator
      .find_by!(external_id: external_id, sway_locale: congress)
      .legislator_terms
      .order(:term_start_year)
      .map { |term| [term.term_start_year, term.term_end_year] }
  end

  def proven_spans(entry)
    entry.dig("terms", "item").map { |term| [term["startYear"], term["endYear"]] }.sort
  end

  it "names people the roster kept because Sway still shows them in office" do
    expect(departed_entries).not_to be_empty,
      "no entry is marked currentMember: false — the roster has lost everybody who left"
  end

  it "leaves each of them holding exactly the terms the published history proves" do
    seed_congress!

    wrong = departed_entries.filter_map { |entry|
      stored = stored_spans(entry["bioguideId"])
      proven = proven_spans(entry)
      next if stored == proven

      "#{entry["bioguideId"]} #{entry["lastName"]}: stored #{stored.inspect}, history proves #{proven.inspect}"
    }

    expect(wrong).to be_empty,
      "a stored term does not match the published history:\n  #{wrong.join("\n  ")}"
  end

  it "leaves no vote filed under a person no term of theirs covers" do
    seed_congress!

    uncovered = LegislatorVote
      .includes(:bill, legislator: {legislator_terms: {district: :sway_locale}})
      .filter_map { |vote|
        bill = vote.bill
        voted_on = bill.house_vote_date_time_utc || bill.senate_vote_date_time_utc
        next if voted_on.nil?
        next if TermWindow.covering(voted_on.to_date, vote.legislator.legislator_terms.to_a)

        "#{vote.legislator.external_id} #{vote.legislator.last_name} voted #{voted_on.to_date} on bill #{bill.id}"
      }

    expect(uncovered).to be_empty,
      "these votes fall outside every term their legislator holds:\n  #{uncovered.join("\n  ")}"
  end

  it "gives nobody two terms running on the same day" do
    seed_congress!

    overlapping = Legislator
      .where(sway_locale: congress)
      .includes(legislator_terms: {district: :sway_locale})
      .filter_map { |legislator|
        running = legislator.legislator_terms.select { |term|
          TermWindow.convening_date(congress, term.term_start_year) <= Date.current &&
            Date.current < TermWindow.ends_on(term)
        }
        next if running.size < 2

        "#{legislator.external_id} #{legislator.last_name}: " \
          "#{running.map { |t| "#{t.term_start_year}-#{t.term_end_year}" }.join(", ")}"
      }

    expect(overlapping).to be_empty,
      "these people hold more than one term running today:\n  #{overlapping.join("\n  ")}"
  end

  # @lat: [[seed-legislator-terms-add-correct-retire#What production_departed_members_spec.rb verifies]]
  it "keeps a departed person in office only while their proven term still runs" do
    seed_congress!

    unexplained = departed_entries.filter_map { |entry|
      legislator = Legislator.find_by!(external_id: entry["bioguideId"], sway_locale: congress)
      term = TermWindow.running_on(Date.current, legislator.legislator_terms.to_a)
      next unless term
      next if proven_spans(entry).include?([term.term_start_year, term.term_end_year])

      "#{entry["bioguideId"]} #{entry["lastName"]} is in office under #{term.term_start_year}-" \
        "#{term.term_end_year}, which the published history does not prove"
    }

    expect(unexplained).to be_empty,
      "these people are still in office under a term nothing proves:\n  #{unexplained.join("\n  ")}"
  end

  # @lat: [[seed-legislator-terms-add-correct-retire#What production_departed_members_spec.rb verifies#The blast radius check]]
  it "leaves every history-backed person holding exactly the terms their history proves" do
    seed_congress!

    marked = roster_entries.select { |entry| entry["termsSource"].present? }
    wrong = marked.filter_map { |entry|
      stored = stored_spans(entry["bioguideId"])
      proven = proven_spans(entry)
      next if stored == proven

      "#{entry["bioguideId"]} #{entry["lastName"]}: stored #{stored.inspect}, history proves #{proven.inspect}"
    }

    expect(wrong).to be_empty,
      "the seed left #{wrong.size} of #{marked.size} people holding terms the history does not prove:\n" \
      "  #{wrong.first(20).join("\n  ")}"
  end

  it "drops nobody the roster still calls a sitting member" do
    seed_congress!

    missing = roster_entries.filter_map { |entry|
      next if entry["currentMember"] == false
      # The President is deliberately given no term, so he is never in office.
      next if entry["bioguideId"] == LegislatorsCache::POTUS_BIOGUIDE_ID

      legislator = Legislator.find_by(external_id: entry["bioguideId"], sway_locale: congress)
      next if legislator && TermWindow.running_on(Date.current, legislator.legislator_terms.to_a)

      "#{entry["bioguideId"]} #{entry["lastName"]}"
    }

    expect(missing).to be_empty,
      "these people are listed as sitting members but hold no term running today:\n  #{missing.join("\n  ")}"
  end

  # db:seed runs on every production boot, so runs two and later must change
  # nothing at all — including the two moves that delete and rewrite rows.
  it "changes nothing on a second run" do
    seed_congress!
    after_first = LegislatorTerm
      .joins(:legislator)
      .where(legislators: {sway_locale_id: congress.id})
      .order(:legislator_id, :term_start_year)
      .pluck(:legislator_id, :term_start_year, :term_end_year, :title, :seat_id)

    seed_congress!
    after_second = LegislatorTerm
      .joins(:legislator)
      .where(legislators: {sway_locale_id: congress.id})
      .order(:legislator_id, :term_start_year)
      .pluck(:legislator_id, :term_start_year, :term_end_year, :title, :seat_id)

    expect(after_second).to eq(after_first)
  end

  # @lat: [[seed-legislator-terms-add-correct-retire#What production_departed_members_spec.rb verifies#Multi-locale snapshot reconciliation]]
  describe "multi-locale production snapshot reconciliation" do
    let(:baltimore) do
      SwayLocale.find_by!(city: "baltimore", state: "maryland", country: "united_states")
    end

    let(:maryland) do
      SwayLocale.find_by!(city: "maryland", state: "maryland", country: "united_states")
    end

    def seed_all_locales!
      SeedSwayLocale.run
      SeedLegislator.run([baltimore, congress, maryland])
    end

    it "persists legislative sessions across all locales even when scalar skip guard fires and returns current session bills for Congress" do
      [baltimore, congress, maryland].each do |loc|
        expect(loc.updated_at).not_to eq(loc.last_seeded_at)
      end

      seed_all_locales!

      [baltimore, congress, maryland].each do |loc|
        expect(loc.reload.updated_at).not_to eq(loc.last_seeded_at)
        expect(loc.legislative_sessions).not_to be_empty
        expect(loc.legislative_sessions.count).to be > 0
      end

      current_bills = Bill.current_session(congress)
      expect(current_bills).not_to be_empty
      expect(current_bills).to be_a(ActiveRecord::Relation)
    end

    it "retires the un-evidenced POTUS term in US0 while preserving person and identifier" do
      seed_all_locales!

      potus = Legislator.find_by!(external_id: "POTUS", sway_locale: congress)
      us0 = District.find_by!(sway_locale: congress, name: "US0")

      expect(potus.legislator_terms.where(district: us0)).to be_empty
      expect(potus.legislator_terms).to be_empty
      expect(potus.first_name).to eq("Donald")
      expect(potus.last_name).to eq("Trump")

      potus_identifier = LegislatorIdentifier.find_by!(
        legislator: potus, sway_locale: congress, source: "bioguide", value: "POTUS"
      )
      expect(potus_identifier).to be_present
    end

    it "attaches distinct seats to every current serving term in Baltimore, Congress, and 191 Maryland roster members" do
      seed_all_locales!

      [baltimore, congress].each do |locale|
        current_terms = LegislatorTerm
          .joins(:legislator)
          .where(legislators: {sway_locale_id: locale.id})
          .current
        expect(current_terms).not_to be_empty

        current_terms.each do |term|
          expect(term.seat_id).to be_present
          seat = term.seat
          expect(seat).to be_present
          next if seat.nil?

          expect(seat.district_id).to eq(term.district_id)
          expect(seat.district.sway_locale_id).to eq(locale.id)
        end
      end

      md_roster_path = Rails.root.join(
        "db", "seeds", "data", "united_states", "maryland", "maryland", "legislators.json"
      )
      md_roster = JSON.parse(md_roster_path.read)
      current_md_entries = md_roster.select { |entry| entry["currentMember"] != false }
      expect(current_md_entries.size).to eq(191)

      current_md_entries.each do |entry|
        legislator = Legislator.find_by!(external_id: entry["id"], sway_locale: maryland)
        term = legislator.active_term
        expect(term).to be_present, "#{legislator.external_id} #{legislator.last_name} holds no term running today"
        next if term.nil?

        expect(term.seat_id).to be_present, "#{legislator.external_id} #{legislator.last_name} has nil seat_id"
        seat = term.seat
        expect(seat).to be_present
        next if seat.nil?

        expect(seat.district_id).to eq(term.district_id)
        expect(seat.district.sway_locale_id).to eq(maryland.id)
      end
    end

    it "reconciles user 1 and user 2 in Congress without raising UnresolvedSeatError and recomputes senator scores" do
      seed_all_locales!

      allow(SwayGeocode).to receive(:build).and_return(double(districts: [0, 3]))

      senator_alsobrooks = Legislator.find_by!(external_id: "A000382", sway_locale: congress)
      senator_van_hollen = Legislator.find_by!(external_id: "V000128", sway_locale: congress)
      rep_elfreth = Legislator.find_by!(external_id: "E000301", sway_locale: congress)

      term_alsobrooks = senator_alsobrooks.active_term
      term_van_hollen = senator_van_hollen.active_term
      expect(term_alsobrooks).to be_present
      expect(term_van_hollen).to be_present
      return if term_alsobrooks.nil? || term_van_hollen.nil?

      [1, 2].each do |user_id|
        user = User.find(user_id)

        expect {
          ReconcileUserDistrictsService.new(user, congress).call
        }.not_to raise_error

        user.reload
        active_uls = user.user_legislators.where(active: true).includes(:legislator)
        active_ids = active_uls.map { |ul| ul.legislator.external_id }

        expect(active_ids).to include("A000382", "V000128", "E000301")

        ul_alsobrooks = user.user_legislators.find_by!(legislator: senator_alsobrooks)
        ul_van_hollen = user.user_legislators.find_by!(legislator: senator_van_hollen)
        ul_elfreth = user.user_legislators.find_by!(legislator: rep_elfreth)

        expect(ul_alsobrooks.active).to be true
        expect(ul_van_hollen.active).to be true
        expect(ul_elfreth.active).to be true

        ScoreRecomputeService.recompute_user_legislator!(ul_alsobrooks, term_alsobrooks)
        ScoreRecomputeService.recompute_user_legislator!(ul_van_hollen, term_van_hollen)

        score_alsobrooks = UserLegislatorTermScore.find_by(
          user_legislator: ul_alsobrooks, legislator_term: term_alsobrooks
        )
        score_van_hollen = UserLegislatorTermScore.find_by(
          user_legislator: ul_van_hollen, legislator_term: term_van_hollen
        )

        expect(score_alsobrooks).to be_present
        expect(score_van_hollen).to be_present
      end
    end
  end
end
