# frozen_string_literal: true

# == Schema Information
#
# Table name: bills
# Database name: primary
#
#  id                         :integer          not null, primary key
#  active                     :boolean
#  amendment_source           :string
#  archived_at                :datetime
#  audio_bucket_path          :string
#  audio_by_line              :string
#  category                   :string           default(""), not null
#  chamber                    :string           not null
#  external_version           :string
#  extracted_text             :text
#  house_vote_date_time_utc   :datetime
#  introduced_date_time_utc   :datetime         not null
#  last_seeded_at             :datetime
#  link                       :string
#  parsed_at                  :datetime
#  parsing_target             :string
#  parsing_target_log         :string
#  scheduled_release_date_utc :date
#  senate_vote_date_time_utc  :datetime
#  status                     :string
#  summary                    :text
#  title                      :string           not null
#  vote_import_state          :string           default("unimported"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  external_id                :string           not null
#  legislative_session_id     :integer
#  legislator_id              :integer          not null
#  sway_locale_id             :integer          not null
#
# Indexes
#
#  idx_bills_on_amendment_source                                 (amendment_source)
#  idx_bills_on_parsing_target                                   (parsing_target)
#  index_bills_on_external_id_and_sway_locale_id                 (external_id,sway_locale_id) UNIQUE
#  index_bills_on_legislative_session_id                         (legislative_session_id)
#  index_bills_on_legislator_id                                  (legislator_id)
#  index_bills_on_locale_and_release_date                        (sway_locale_id,scheduled_release_date_utc)
#  index_bills_on_scheduled_release_date_utc_and_sway_locale_id  (scheduled_release_date_utc,sway_locale_id) UNIQUE
#  index_bills_on_sway_locale_id                                 (sway_locale_id)
#  index_bills_on_sway_locale_id_and_archived_at                 (sway_locale_id,archived_at)
#  index_bills_on_vote_import_state                              (vote_import_state)
#
# Foreign Keys
#
#  legislative_session_id  (legislative_session_id => legislative_sessions.id) ON DELETE => nullify
#  legislator_id           (legislator_id => legislators.id)
#  sway_locale_id          (sway_locale_id => sway_locales.id)
#
RSpec.describe Bill, type: :model do
  context "an instance of Bill" do
    # How to test an Active Record callback: https://stackoverflow.com/a/16678194/6410635
    it "creates a default bill score after create" do
      bill = create(:bill)
      expect(bill.reload.bill_score).to be_a(BillScore)
    end

    it "has a downcased status after save" do
      bill = build(:bill, status: Bill::Status::PASSED.upcase)
      bill.save
      expect(bill.status).to eql(Bill::Status::PASSED.downcase)
    end

    it "writes an unrelated column on a row whose stored status is off the allowlist" do
      bill = create(:bill)
      bill.update_column(:status, "Committee Referral")
      bill.reload
      date = Time.zone.parse("2026-01-02 12:00:00")

      expect(bill.update(house_vote_date_time_utc: date)).to be(true)
      expect(bill.reload.house_vote_date_time_utc).to eq(date)
      expect(bill.status).to eq("Committee Referral")
    end

    it "refuses a newly assigned status that is off the allowlist, naming the value" do
      bill = create(:bill)

      bill.status = "Committee Referral"

      expect(bill).not_to be_valid
      expect(bill.errors[:status]).to include(a_string_matching(/Committee Referral/))
    end
  end

  describe "status blankness constraints" do
    let(:bill) { create(:bill) }

    describe "model validation" do
      it "refuses saving a bill with an empty string status" do
        new_bill = build(:bill, status: "")
        expect(new_bill).not_to be_valid
        expect(new_bill.errors[:status]).to include("Status can't be blank")
      end

      it "refuses saving a bill with a whitespace-only status" do
        new_bill = build(:bill, status: "   ")
        expect(new_bill).not_to be_valid
        expect(new_bill.errors[:status]).to include("Status can't be blank")
      end

      it "refuses saving a bill with a nil status" do
        new_bill = build(:bill, status: nil)
        expect(new_bill).not_to be_valid
        expect(new_bill.errors[:status]).to include("Status can't be blank")
      end

      it "refuses updating an existing bill with an empty string status" do
        bill.status = ""
        expect(bill).not_to be_valid
        expect(bill.errors[:status]).to include("Status can't be blank")
      end

      it "refuses updating an existing bill with whitespace status" do
        bill.status = "   "
        expect(bill).not_to be_valid
        expect(bill.errors[:status]).to include("Status can't be blank")
      end

      it "refuses Unicode whitespace statuses at the model validation layer" do
        ["\u00A0", "\u200B", "\u3000"].each do |unicode_ws|
          candidate = build(:bill, status: unicode_ws)
          expect(candidate).not_to be_valid
          expect(candidate.errors[:status]).to be_present
        end
      end
    end

    describe "database check constraint" do
      # @lat: [[bill-status-normalisation#Database check constraint against blank status]]
      blank_statuses = [nil, "", "   ", "\t", "\n", "\r\n", "\t \n\r ", "\u00A0", "\u200B", "\u3000"]
      valid_statuses = Bill::STATUSES + ["Committee Referral"]

      describe "rejecting blank and whitespace statuses" do
        blank_statuses.each_with_index do |blank_val, idx|
          it "refuses setting status to #{blank_val.inspect} via update_column with a CHECK constraint error" do
            expect {
              bill.update_column(:status, blank_val)
            }.to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint failed/i)
          end

          it "refuses raw SQL update setting status to #{blank_val.inspect}" do
            sql = if blank_val.nil?
              "UPDATE bills SET status = NULL WHERE id = #{bill.id}"
            else
              ActiveRecord::Base.sanitize_sql_array([
                "UPDATE bills SET status = ? WHERE id = ?",
                blank_val,
                bill.id
              ])
            end
            expect {
              ActiveRecord::Base.connection.execute(sql)
            }.to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint failed/i)
          end

          it "refuses raw SQL insert with #{blank_val.inspect} status" do
            locale = bill.sway_locale
            legislator = bill.legislator
            sql = if blank_val.nil?
              "INSERT INTO bills (external_id, title, chamber, introduced_date_time_utc, sway_locale_id, legislator_id, status, created_at, updated_at) " \
                "VALUES ('check-constraint-test-blank-#{idx}', 'Check Test', 'council', '2026-01-01 00:00:00', #{locale.id}, #{legislator.id}, NULL, datetime('now'), datetime('now'))"
            else
              ActiveRecord::Base.sanitize_sql_array([
                "INSERT INTO bills (external_id, title, chamber, introduced_date_time_utc, sway_locale_id, legislator_id, status, created_at, updated_at) " \
                "VALUES (?, 'Check Test', 'council', '2026-01-01 00:00:00', ?, ?, ?, datetime('now'), datetime('now'))",
                "check-constraint-test-blank-#{idx}",
                locale.id,
                legislator.id,
                blank_val
              ])
            end
            expect {
              ActiveRecord::Base.connection.execute(sql)
            }.to raise_error(ActiveRecord::StatementInvalid, /CHECK constraint failed/i)
          end
        end
      end

      describe "allowing valid and legacy statuses" do
        valid_statuses.each_with_index do |valid_val, idx|
          it "allows valid status #{valid_val.inspect} through update_column" do
            expect {
              bill.update_column(:status, valid_val)
            }.not_to raise_error
            expect(bill.reload.status).to eq(valid_val)
          end

          it "allows valid status #{valid_val.inspect} through raw SQL update" do
            sql = ActiveRecord::Base.sanitize_sql_array([
              "UPDATE bills SET status = ? WHERE id = ?",
              valid_val,
              bill.id
            ])
            expect {
              ActiveRecord::Base.connection.execute(sql)
            }.not_to raise_error
            expect(bill.reload.status).to eq(valid_val)
          end

          it "allows valid status #{valid_val.inspect} through raw SQL insert" do
            locale = bill.sway_locale
            legislator = bill.legislator
            unique_id = "check-constraint-test-valid-#{idx}"
            sql = ActiveRecord::Base.sanitize_sql_array([
              "INSERT INTO bills (external_id, title, chamber, introduced_date_time_utc, sway_locale_id, legislator_id, status, created_at, updated_at) " \
              "VALUES (?, 'Check Test', 'council', '2026-01-01 00:00:00', ?, ?, ?, datetime('now'), datetime('now'))",
              unique_id,
              locale.id,
              legislator.id,
              valid_val
            ])
            expect {
              ActiveRecord::Base.connection.execute(sql)
            }.not_to raise_error
            expect(Bill.find_by(external_id: unique_id)&.status).to eq(valid_val)
          end
        end
      end
    end
  end

  context "querying the bill of the month" do
    it "is the bill of the month" do
      sway_locale = create(:sway_locale)
      bill = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.today - 2.days)
      bill_2 = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.today)
      expect(bill_2.sway_locale).to eql(bill.sway_locale)
      expect(Bill.of_the_month(sway_locale: bill_2.sway_locale)).to_not eql(bill)
      expect(Bill.of_the_month(sway_locale: bill_2.sway_locale)).to eql(bill_2)
    end

    it "returns only previous released bills of the month in Bill.past_of_the_month" do
      sway_locale = create(:sway_locale)
      older_botm = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.today - 10.days)
      recent_botm = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.today - 2.days)
      current_botm = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.today)
      future_botm = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: Time.zone.today + 5.days)
      unscheduled_bill = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: nil)

      past_bills = Bill.past_of_the_month(sway_locale: sway_locale).order(scheduled_release_date_utc: :desc)

      expect(past_bills).to eq([recent_botm, older_botm])
      expect(past_bills).not_to include(current_botm, future_botm, unscheduled_bill)
    end

    it "scopes bills to a legislative session and unscopes archived_at for inactive historical sessions" do
      sway_locale = create(:sway_locale)
      active_session = create(:legislative_session, sway_locale: sway_locale, name: "2026 Session", active: true)
      historical_session = create(:legislative_session, sway_locale: sway_locale, name: "2024 Session", active: false)

      active_bill = create(:bill, sway_locale: sway_locale, legislative_session: active_session)
      active_archived_bill = create(:bill, sway_locale: sway_locale, legislative_session: active_session, archived_at: Time.current)
      historical_archived_bill = create(:bill, sway_locale: sway_locale, legislative_session: historical_session, archived_at: Time.current)

      expect(Bill.for_legislative_session(active_session)).to contain_exactly(active_bill)
      expect(Bill.for_legislative_session(active_session)).not_to include(active_archived_bill)
      expect(Bill.for_legislative_session(historical_session)).to contain_exactly(historical_archived_bill)
    end
  end

  describe "associations" do
    it "optionally belongs to a legislative_session" do
      bill = create(:bill, legislative_session: nil)
      expect(bill.legislative_session).to be_nil
    end

    it "persists association with a legislative_session" do
      session = create(:legislative_session)
      bill = create(:bill, sway_locale: session.sway_locale, legislative_session: session)
      expect(bill.reload.legislative_session).to eq(session)
    end

    it "has many bill_news_articles and news_articles through bill_news_articles" do
      bill = create(:bill)
      article = create(:news_article)
      bna = create(:bill_news_article, bill:, news_article: article)

      expect(bill.bill_news_articles).to include(bna)
      expect(bill.news_articles).to include(article)
    end

    it "destroys associated bill_news_articles when the bill is destroyed while preserving shared news_articles" do
      bill = create(:bill)
      article = create(:news_article)
      create(:bill_news_article, bill:, news_article: article)

      expect { bill.destroy }.to change(BillNewsArticle, :count).by(-1)
      expect(NewsArticle.exists?(article.id)).to be true
    end
  end

  describe "#active and #active?" do
    context "when bill is associated with an active legislative session" do
      it "returns true regardless of database active column" do
        sway_locale = create(:sway_locale)
        active_session = create(:legislative_session, :active, sway_locale:)
        bill_true = build(:bill, sway_locale:, legislative_session: active_session, active: true)
        bill_false = build(:bill, sway_locale:, legislative_session: active_session, active: false)
        expect(bill_true.active).to be true
        expect(bill_true.active?).to be true
        expect(bill_false.active).to be true
        expect(bill_false.active?).to be true
      end
    end

    context "when bill is associated with an inactive legislative session" do
      it "returns false regardless of database active column" do
        sway_locale = create(:sway_locale)
        inactive_session = create(:legislative_session, active: false, sway_locale:)
        bill_true = build(:bill, sway_locale:, legislative_session: inactive_session, active: true)
        bill_false = build(:bill, sway_locale:, legislative_session: inactive_session, active: false)
        expect(bill_true.active).to be false
        expect(bill_true.active?).to be false
        expect(bill_false.active).to be false
        expect(bill_false.active?).to be false
      end
    end

    context "when legislative_session is nil" do
      it "falls back to super.nil? || super" do
        sway_locale = create(:sway_locale)
        bill_nil = build(:bill, sway_locale:, legislative_session: nil, active: nil)
        bill_true = build(:bill, sway_locale:, legislative_session: nil, active: true)
        bill_false = build(:bill, sway_locale:, legislative_session: nil, active: false)

        expect(bill_nil.active).to be true
        expect(bill_nil.active?).to be true
        expect(bill_true.active).to be true
        expect(bill_true.active?).to be true
        expect(bill_false.active).to be false
        expect(bill_false.active?).to be false
      end
    end
  end

  describe ".current_legislative_session" do
    it "filters bills by active sessions and locale" do
      locale_a = create(:sway_locale, :baltimore)
      locale_b = create(:sway_locale, :congress)
      session_a_active = create(:legislative_session, :active, sway_locale: locale_a)
      session_a_inactive = create(:legislative_session, active: false, sway_locale: locale_a)
      session_b_active = create(:legislative_session, :active, sway_locale: locale_b)

      bill_a_active = create(:bill, sway_locale: locale_a, legislative_session: session_a_active, scheduled_release_date_utc: 1.day.ago)
      create(:bill, sway_locale: locale_a, legislative_session: session_a_inactive, scheduled_release_date_utc: 2.days.ago)
      bill_a_nil_active = create(:bill, sway_locale: locale_a, legislative_session: nil, scheduled_release_date_utc: 3.days.ago, introduced_date_time_utc: session_a_active.start_date + 1.day)
      create(:bill, sway_locale: locale_a, legislative_session: nil, scheduled_release_date_utc: 4.days.ago, introduced_date_time_utc: session_a_active.start_date - 1.day)
      bill_b_active = create(:bill, sway_locale: locale_b, legislative_session: session_b_active, scheduled_release_date_utc: 5.days.ago)

      expect(described_class.current_legislative_session(locale_a)).to contain_exactly(bill_a_active, bill_a_nil_active)
      expect(described_class.current_legislative_session(locale_a.id)).to contain_exactly(bill_a_active, bill_a_nil_active)
      expect(described_class.current_legislative_session).to contain_exactly(bill_a_active, bill_a_nil_active, bill_b_active)
      expect(described_class.current_session(locale_a)).to eq(described_class.current_legislative_session(locale_a))
    end
  end

  describe "validations" do
    it "is invalid without an external_id" do
      bill = build(:bill, external_id: nil)
      expect(bill).not_to be_valid
    end

    describe "link validation" do
      let(:legislator) { create(:legislator) }

      it "allows link to be nil" do
        bill = build(:bill, legislator: legislator, link: nil)
        expect(bill).to be_valid
        expect { bill.save! }.not_to raise_error
      end

      it "allows multiple bills with link: nil without uniqueness collision" do
        bill1 = create(:bill, link: nil)
        bill2 = build(:bill, legislator: legislator, link: nil)

        expect(bill2).to be_valid
        expect { bill2.save! }.not_to raise_error
        expect(bill1.reload.link).to be_nil
        expect(bill2.reload.link).to be_nil
      end

      it "enforces uniqueness for non-nil links" do
        shared_url = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=123&GUID=abc"
        create(:bill, link: shared_url)
        duplicate = build(:bill, legislator: legislator, link: shared_url)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:link]).to be_present
      end

      it "normalizes blank and whitespace links to nil" do
        bill = build(:bill, legislator: legislator, link: "   ")
        expect(bill).to be_valid
        bill.save!
        expect(bill.reload.link).to be_nil
      end
    end
  end

  describe "after_commit on whitelisted vote-trigger fields" do
    # @lat: [[legislator-vote-fetch-job-design#Why the whitelisted-field spec picks its replacement values carefully]]
    let(:bill) { create(:bill, external_id: "old-id", status: "committee") }

    # Pick a status DIFFERENT from the bill's current status. Bill::STATUSES
    # is %w[passed failed committee vetoed]; the bill above starts at
    # "committee", so pick anything else.
    # steep:ignore:start
    def alternate_status_for(current)
      (Bill::STATUSES - [current]).first
    end

    # Pick a chamber value the model accepts that differs from current.
    # The Bill factory defaults to "council"; choose another model-allowed
    # chamber value (house/senate/council).
    def alternate_chamber_for(current)
      %w[house senate council].find { |c| c != current.to_s.downcase } ||
        "house"
    end
    # steep:ignore:end

    it "enqueues LegislatorVoteFetchJob when external_id changes" do
      expect {
        bill.update!(external_id: "new-id")
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).exactly(1).times
    end

    it "enqueues LegislatorVoteFetchJob when external_version changes" do
      expect {
        bill.update!(external_version: "v2-#{rand(1000)}")
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).exactly(1).times
    end

    it "enqueues LegislatorVoteFetchJob when chamber changes (REVIEWS MEDIUM: uses model-allowed chamber value)" do
      new_chamber = alternate_chamber_for(bill.chamber)
      skip "no alternate chamber available" if new_chamber == bill.chamber.to_s.downcase
      expect {
        bill.update!(chamber: new_chamber)
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).exactly(1).times
    end

    it "enqueues LegislatorVoteFetchJob when status changes (REVIEWS MEDIUM: uses Bill::STATUSES value)" do
      new_status = alternate_status_for(bill.status)
      expect(Bill::STATUSES).to include(new_status) # make sure the schema allows this value
      expect {
        bill.update!(status: new_status)
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).exactly(1).times
    end

    it "enqueues LegislatorVoteFetchJob when house_vote_date_time_utc changes" do
      expect {
        bill.update!(house_vote_date_time_utc: Time.current)
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).exactly(1).times
    end

    it "enqueues LegislatorVoteFetchJob when senate_vote_date_time_utc changes" do
      expect {
        bill.update!(senate_vote_date_time_utc: Time.current)
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).exactly(1).times
    end

    it "does NOT enqueue when a non-whitelisted field changes" do
      expect {
        bill.update!(title: "new title that is not whitelisted")
      }.not_to have_enqueued_job(LegislatorVoteFetchJob)
    end

    it "does NOT enqueue on Bill creation (on: :update only)" do
      expect {
        create(:bill, external_id: "fresh", external_version: "v1")
      }.not_to have_enqueued_job(LegislatorVoteFetchJob)
    end

    it "enqueues exactly once when multiple whitelisted fields change in one save" do
      new_status = alternate_status_for(bill.status)
      expect {
        bill.update!(external_id: "x", external_version: "v2", status: new_status)
      }.to have_enqueued_job(LegislatorVoteFetchJob).with(bill.id).exactly(1).times
    end
  end

  describe "#to_sway_json categories" do
    it "includes a categories array with the names of associated categories" do
      bill = create(:bill)
      cat_a = create(:category, name: "Budget")
      cat_b = create(:category, name: "Zoning")
      create(:bill_category, bill: bill, category: cat_a)
      create(:bill_category, bill: bill, category: cat_b)

      result = bill.reload.to_sway_json
      expect(result["categories"]).to match_array(["Budget", "Zoning"])
    end

    it "serializes an empty categories array when a bill has no categories" do
      bill = create(:bill)
      result = bill.to_sway_json
      expect(result["categories"]).to eq([])
    end

    # @lat: [[bill-json-payload-design#Why categories uses .map(&:name), not .pluck(:name)]]
    it "excludes soft-inactive categories from the public categories array (IN-01)" do
      bill = create(:bill)
      active_cat = create(:category, name: "Housing", active: true)
      inactive_cat = create(:category, name: "OldTopic", active: false)
      create(:bill_category, bill: bill, category: active_cat)
      create(:bill_category, bill: bill, category: inactive_cat)

      result = bill.reload.to_sway_json
      expect(result["categories"]).to include("Housing")
      expect(result["categories"]).not_to include("OldTopic")
    end
  end

  describe "interesting-score recompute trigger on create" do
    # @lat: [[bill-score-recompute-callback-split#Bill trigger fields separate vote fetching from score recomputation]]
    it "enqueues RecomputeBillInterestingScoreJob when a bill is created" do
      expect {
        create(:bill)
      }.to have_enqueued_job(RecomputeBillInterestingScoreJob)
        .with { |bill_id| expect(bill_id).to eq(Bill.order(:id).last&.id) }
        .exactly(1).times
    end

    # @lat: [[bill-score-recompute-callback-split#Why one combined callback does not work]]
    it "enqueues the recompute for a bill created-then-updated inside one transaction (iter-2 WR-01)" do
      expect {
        Bill.transaction do
          bill = create(:bill)
          bill.update!(title: "renamed inside the creating transaction")
        end
      }.to have_enqueued_job(RecomputeBillInterestingScoreJob)
        .with { |bill_id| expect(bill_id).to eq(Bill.order(:id).last&.id) }
        .exactly(1).times
    end

    it "still enqueues on score-trigger field updates and not on unrelated updates" do
      bill = create(:bill)
      expect {
        bill.update!(house_vote_date_time_utc: Time.current)
      }.to have_enqueued_job(RecomputeBillInterestingScoreJob).with(bill.id).exactly(1).times
      expect {
        bill.update!(title: "unrelated title change")
      }.not_to have_enqueued_job(RecomputeBillInterestingScoreJob)
    end

    # @lat: [[bill-score-trigger-fields-locale-inclusion#Why both lists use after_commit plus saved_change_to_attribute?]]
    it "enqueues the recompute when a bill moves to another sway_locale (review WR-01)" do
      bill = create(:bill)
      other_locale = create(:sway_locale, city: "Otherville", state: "MD", country: "United States")
      expect {
        bill.update!(sway_locale_id: other_locale.id)
      }.to have_enqueued_job(RecomputeBillInterestingScoreJob).with(bill.id).exactly(1).times
    end
  end

  describe "destroying a bill with interesting-score rows" do
    # @lat: [[bill-interesting-score-design#Why Bill needs dependent: :delete_all on bill_interesting_scores]]
    it "does not raise ActiveRecord::InvalidForeignKey when >= 2 score rows exist" do
      bill = create(:bill)
      BillInterestingScoreCalculator.new(bill).call
      BillInterestingScoreCalculator.new(bill).call
      expect(BillInterestingScore.where(bill_id: bill.id).count).to be >= 2

      expect { bill.destroy! }.not_to raise_error
      expect(BillInterestingScore.where(bill_id: bill.id).count).to eq(0)
    end
  end

  describe "#latest_legislation_pipeline_run" do
    let(:fresh_bill) { create(:bill, external_id: "latest-run-test", status: "committee") }

    it "returns the most recently created run, not the oldest" do
      first_run = LegislationPipelineRun.create!(bill: fresh_bill, stages: ["fetch-bills"], status: "failed", remote_run_id: "old", created_at: 2.hours.ago)
      latest_run = LegislationPipelineRun.create!(bill: fresh_bill, stages: ["fetch-bills"], status: "succeeded", remote_run_id: "new", created_at: 1.minute.ago)
      expect(fresh_bill.latest_legislation_pipeline_run).to eq(latest_run)
      expect(fresh_bill.latest_legislation_pipeline_run).not_to eq(first_run)
    end

    it "returns nil when the bill has no pipeline runs" do
      expect(fresh_bill.latest_legislation_pipeline_run).to be_nil
    end
  end

  # The overridden `organization_bill_positions` reader that hid inactive rows is
  # gone. Getting only the active ones is now its own named association.
  describe "organization_bill_positions honesty" do
    let(:bill) { create(:bill) }

    it "returns inactive rows too (the reader no longer hides them)" do
      active = create(:organization_bill_position, bill: bill, active: true)
      inactive = create(:organization_bill_position, bill: bill, active: false)
      expect(bill.organization_bill_positions).to include(active, inactive)
    end

    it "exposes only active rows via active_organization_bill_positions" do
      active = create(:organization_bill_position, bill: bill, active: true)
      inactive = create(:organization_bill_position, bill: bill, active: false)
      expect(bill.active_organization_bill_positions).to include(active)
      expect(bill.active_organization_bill_positions).not_to include(inactive)
    end

    it "still serializes only active organizations via #organizations" do
      active = create(:organization_bill_position, bill: bill, active: true)
      create(:organization_bill_position, bill: bill, active: false)
      expect(bill.organizations).to contain_exactly(active.organization)
    end

    it "cascades all positions on destroy, active and inactive" do
      create(:organization_bill_position, bill: bill, active: true)
      create(:organization_bill_position, bill: bill, active: false)
      expect { bill.destroy }.to change { OrganizationBillPosition.count }.by(-2)
    end
  end

  # @lat: [[bill-external-id-validation#Why external IDs require path validation]]
  describe "external_id format (A1-CR-02)" do
    # @lat: [[bill-external-id-validation#Why the format spec updates a saved bill instead of using build(:bill)]]
    def bill_with_external_id(value)
      bill = create(:bill, scheduled_release_date_utc: nil)
      bill.external_id = value
      bill
    end

    it "accepts the shapes the three supported locales use" do
      %w[24-0599 HB1234 SB567 hr815 S.J.Res.12 CB_23-0312].each do |id|
        bill = bill_with_external_id(id)

        expect(bill).to be_valid, "expected #{id.inspect} to be a valid external_id"
      end
    end

    [
      ["a parent-directory escape", "../../../../rails/config/pwned"],
      ["an embedded parent reference", "24-0599/../../etc"],
      ["an absolute path", "/etc/passwd"],
      ["a nested path segment", "24-0599/nested"],
      ["a leading dot", ".ssh"],
      ["a glob metacharacter", "24-*"],
      ["a space", "24 0599"]
    ].each do |label, value|
      it "rejects #{label}" do
        bill = bill_with_external_id(value)

        expect(bill).not_to be_valid
        expect(bill.errors[:external_id]).to be_present
      end
    end

    it "rejects an id past the 64-character bound" do
      bill = bill_with_external_id("A" * 65)

      expect(bill).not_to be_valid
      expect(bill.errors[:external_id]).to be_present
    end

    # @lat: [[bill-external-id-validation#Why a stored external_id is stripped rather than rejected]]
    it "strips surrounding whitespace rather than rejecting it" do
      bill = create(:bill, external_id: "\t24-0599 ")

      expect(bill.reload.external_id).to eq("24-0599")
    end

    # @lat: [[bill-external-id-normalisation#Why the check is conditional]]
    it "does not block an unrelated save on a legacy row, and repairs it in passing" do
      bill = create(:bill)
      Bill.where(id: bill.id).update_all(external_id: "\t24-0599")
      legacy = Bill.find(bill.id)

      expect { legacy.update!(title: "A new title") }.not_to raise_error
      expect(legacy.reload.external_id).to eq("24-0599")
      expect(legacy.title).to eq("A new title")
    end

    it "still rejects a hostile value written onto an existing row" do
      bill = bill_with_external_id("../../../../rails/config/pwned")

      expect(bill).not_to be_valid
      expect { bill.save! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  # The notice on machine-written text nobody has revised.
  describe "#summary_ai_unreviewed?" do
    it "is true while the published summary is still the model's draft" do
      bill = create(:bill, summary: "The model wrote this.")
      create(
        :bill_llm_provisioning,
        bill: bill, llm_summary: "The model wrote this.", llm_provider: "claude"
      )

      expect(bill.reload.summary_ai_unreviewed?).to be(true)
    end

    it "is false once a person revises the published summary" do
      bill = create(:bill, summary: "The model wrote this.")
      create(
        :bill_llm_provisioning,
        bill: bill, llm_summary: "The model wrote this.", llm_provider: "claude"
      )

      bill.update!(summary: "A person rewrote this.")

      expect(bill.reload.summary_ai_unreviewed?).to be(false)
    end

    it "is false for a bill with no provisioning row" do
      bill = create(:bill, summary: "Typed in by an admin.")

      expect(bill.summary_ai_unreviewed?).to be(false)
    end

    # The state a bill sits in between ingestion and its first run: a row
    # exists because the pipeline made one, and no model has written yet.
    it "is false for the placeholder summary while no draft exists" do
      bill = create(:bill, summary: Bill::SUMMARY_PLACEHOLDER)
      create(:bill_llm_provisioning, bill: bill, llm_summary: nil)

      expect(bill.reload.summary_ai_unreviewed?).to be(false)
    end

    # A paste is hand-written work everywhere else in this codebase — it is
    # what the supersede gate protects — so it is not a machine's words here.
    it "is false for a pasted body, even when the two texts match" do
      bill = create(:bill, summary: "An operator pasted this.")
      create(
        :bill_llm_provisioning,
        bill: bill,
        llm_summary: "An operator pasted this.",
        llm_provider: BillLlmProvisioning::OPERATOR_PASTE_PROVIDER
      )

      expect(bill.reload.summary_ai_unreviewed?).to be(false)
    end

    it "ships the answer on to_builder, so every reader gets the same one" do
      bill = create(:bill, summary: "The model wrote this.")
      create(
        :bill_llm_provisioning,
        bill: bill, llm_summary: "The model wrote this.", llm_provider: "claude"
      )

      expect(bill.reload.to_sway_json["summary_ai_unreviewed"]).to be(true)
    end

    it "preserves unreviewed status when an unreviewed revision is restored" do
      bill = create(:bill, summary: "Generated unreviewed A")
      prov = create(:bill_llm_provisioning, bill: bill, llm_summary: "Generated unreviewed A", llm_provider: "claude")

      rev_a = BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "Generated unreviewed A",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed",
        llm_provider: "claude"
      )

      # Later draft B is generated
      prov.update!(llm_summary: "Generated draft B")
      BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "Generated draft B",
        origin: "model_generation",
        publication_role: "draft",
        review_state: "unreviewed",
        llm_provider: "claude"
      )

      # Restore unreviewed revision A
      bill.restore_summary_revision!(rev_a)

      expect(bill.reload.summary_ai_unreviewed?).to be(true)
      expect(bill.reload.to_sway_json["summary_ai_unreviewed"]).to be(true)
    end

    it "preserves reviewed status when a reviewed revision is restored" do
      bill = create(:bill, summary: "Operator reviewed A")
      create(:bill_llm_provisioning, bill: bill, llm_summary: "Draft B", llm_provider: "claude")

      rev_reviewed = BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "Operator reviewed A",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed"
      )

      # Restore reviewed revision A
      bill.restore_summary_revision!(rev_reviewed)

      expect(bill.reload.summary_ai_unreviewed?).to be(false)
      expect(bill.reload.to_sway_json["summary_ai_unreviewed"]).to be(false)
    end

    it "later draft capture cannot change the warning for an unchanged published summary" do
      bill = create(:bill, summary: "Generated unreviewed A")
      prov = create(:bill_llm_provisioning, bill: bill, llm_summary: "Generated unreviewed A", llm_provider: "claude")

      BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "Generated unreviewed A",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed",
        llm_provider: "claude"
      )
      expect(bill.reload.summary_ai_unreviewed?).to be(true)

      # Later draft B is captured but withheld from publication
      prov.update!(llm_summary: "Generated draft B")
      BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "Generated draft B",
        origin: "model_generation",
        publication_role: "draft",
        review_state: "unreviewed",
        llm_provider: "claude"
      )

      # Published summary is still A; warning must remain true
      expect(bill.reload.summary_ai_unreviewed?).to be(true)
    end

    it "returns false when published revision is reviewed even if provisioning.llm_summary has identical text" do
      shared_text = "Identical text that was reviewed by an operator"
      bill = create(:bill, summary: shared_text)
      create(:bill_llm_provisioning, bill: bill, llm_summary: shared_text, llm_provider: "claude")

      BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: shared_text,
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed"
      )

      expect(bill.reload.summary_ai_unreviewed?).to be(false)
    end

    it "returns false when provisioning is absent, pending without llm_summary, or from OPERATOR_PASTE_PROVIDER" do
      bill_no_prov = create(:bill, summary: "Summary without provisioning")
      expect(bill_no_prov.summary_ai_unreviewed?).to be(false)

      bill_pending = create(:bill, summary: "Summary while generation pending")
      create(:bill_llm_provisioning, :pending, bill: bill_pending, llm_summary: nil, llm_provider: "claude")
      expect(bill_pending.summary_ai_unreviewed?).to be(false)

      bill_pasted = create(:bill, summary: "Pasted text")
      create(
        :bill_llm_provisioning,
        bill: bill_pasted,
        llm_summary: "Pasted text",
        llm_provider: BillLlmProvisioning::OPERATOR_PASTE_PROVIDER
      )
      expect(bill_pasted.summary_ai_unreviewed?).to be(false)
    end

    it "returns false when restoring an unknown-provenance revision or after direct summary column edit" do
      bill = create(:bill, summary: "Initial legacy summary")
      prov = create(:bill_llm_provisioning, bill: bill, llm_summary: "New AI draft", llm_provider: "claude")

      rev_baseline = BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "Initial legacy summary",
        origin: "initial_baseline",
        publication_role: "published",
        review_state: "unknown"
      )
      rev_unreviewed = BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "New AI draft",
        origin: "model_generation",
        publication_role: "published",
        review_state: "unreviewed",
        llm_provider: "claude"
      )
      bill.restore_summary_revision!(rev_unreviewed, news_usage: "none")
      expect(bill.reload.summary_ai_unreviewed?).to be(true)

      bill.restore_summary_revision!(rev_baseline, news_usage: "none")
      expect(bill.reload.summary_ai_unreviewed?).to be(false)

      bill.restore_summary_revision!(rev_unreviewed, news_usage: "none")
      expect(bill.reload.summary_ai_unreviewed?).to be(true)

      prov.update!(llm_summary: "Second draft text")
      BillSummaryRevision.record_revision!(
        bill: bill,
        summary_markdown: "Second draft text",
        origin: "model_generation",
        publication_role: "draft",
        review_state: "unreviewed",
        llm_provider: "claude"
      )
      expect(bill.reload.summary_ai_unreviewed?).to be(true)

      bill.update_columns(summary: "Direct DB column tweak")
      expect(bill.reload.summary_ai_unreviewed?).to be(false)
    end
  end

  # @lat: [[bill-of-the-month-no-redirect-on-empty#Why an empty Bill of the Month stays on the page]]
  # @lat: [[bootstrap-caching-and-rate-limiting#Why locale and featured bill are cached per locale]]
  # @lat: [[query-plan-indexes#Bill of the month reads by locale then date]]
  describe ".of_the_month query plan" do
    it "uses index_bills_on_locale_and_release_date without a full table scan" do
      locale = create(:sway_locale)
      create(:bill, sway_locale: locale, scheduled_release_date_utc: Time.zone.today)

      statements = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        sql = payload[:sql].to_s
        statements << sql if payload[:name] != "SCHEMA" && !payload[:cached] && sql.include?('FROM "bills"')
      end
      begin
        described_class.of_the_month(sway_locale: locale)
      ensure
        ActiveSupport::Notifications.unsubscribe(sub)
      end

      expect(statements).not_to be_empty
      statements.each do |sql|
        plan_rows = ActiveRecord::Base.connection.exec_query("EXPLAIN QUERY PLAN #{sql}").to_a
        details = plan_rows.map { |r| r["detail"].to_s }.join(" | ")

        expect(details).to include("USING INDEX index_bills_on_locale_and_release_date")
        expect(details).not_to match(/\bSCAN\b/i)
      end
    end
  end
end
