require "rails_helper"
require Rails.root.join("db", "seeds", "models", "development_user_graph")

RSpec.describe SeedDevelopmentUserGraph do
  let(:baltimore) do
    create(
      :sway_locale,
      city: "baltimore",
      state: "maryland",
      country: "United States"
    )
  end
  let(:other_locale) do
    create(
      :sway_locale,
      city: "congress",
      state: "congress",
      country: "United States"
    )
  end

  let!(:at_large_district) { create(:district, sway_locale: baltimore, name: "MD0") }
  let!(:district_one) { create(:district, sway_locale: baltimore, name: "MD1") }
  let!(:district_two) { create(:district, sway_locale: baltimore, name: "MD2") }
  let!(:district_three) { create(:district, sway_locale: baltimore, name: "MD3") }

  # @lat: [[seeded-development-users#Score refresh follows current legislator terms]]
  let!(:council_president) do
    create(
      :legislator,
      district: at_large_district,
      title: "Council President",
      external_id: "council-president",
      first_name: "Odette",
      last_name: "Baxter"
    ).tap { |legislator| create(:legislator_term, legislator:, district: at_large_district, title: "Council President") }
  end
  let!(:district_one_legislator) do
    create(
      :legislator,
      district: district_one,
      title: "Council Member",
      external_id: "district-one",
      first_name: "Jules",
      last_name: "Carter"
    ).tap { |legislator| create(:legislator_term, legislator:, district: district_one, title: "Council Member") }
  end
  let!(:district_two_legislator) do
    create(
      :legislator,
      district: district_two,
      title: "Council Member",
      external_id: "district-two",
      first_name: "Mina",
      last_name: "Diaz"
    ).tap { |legislator| create(:legislator_term, legislator:, district: district_two, title: "Council Member") }
  end
  let!(:district_three_legislator) do
    create(
      :legislator,
      district: district_three,
      title: "Council Member",
      external_id: "district-three",
      first_name: "Theo",
      last_name: "Evans"
    ).tap { |legislator| create(:legislator_term, legislator:, district: district_three, title: "Council Member") }
  end
  let!(:mayor) do
    create(
      :legislator,
      district: at_large_district,
      title: "Mayor",
      external_id: "mayor",
      first_name: "Ada",
      last_name: "Foster"
    ).tap { |legislator| create(:legislator_term, legislator:, district: at_large_district, title: "Mayor") }
  end

  let!(:bills) do
    3.times.map do |index|
      create(
        :bill,
        sway_locale: baltimore,
        legislator: council_president,
        external_id: "baltimore-bill-#{index}",
        title: "Baltimore Bill #{index}",
        introduced_date_time_utc: (index + 1).days.ago,
        scheduled_release_date_utc: nil
      )
    end
  end
  let!(:other_bill) do
    other_district = create(:district, sway_locale: other_locale, name: "US0")
    other_legislator =
      create(
        :legislator,
        district: other_district,
        title: "Representative",
        external_id: "other-locale-legislator"
      )

    create(
      :bill,
      sway_locale: other_locale,
      legislator: other_legislator,
      external_id: "other-bill",
      title: "Other Locale Bill",
      scheduled_release_date_utc: nil
    )
  end

  describe ".enabled?" do
    it "is false outside development by default" do
      expect(described_class.enabled?).to be(false)
    end

    it "is false for preview databases even when Rails.env is development" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SWAY_DATABASE_NAME", "").and_return("storage/preview.sqlite3")

      expect(described_class.enabled?).to be(false)
    end
  end

  describe ".run" do
    before do
      allow(described_class).to receive(:enabled?).and_return(true)
    end

    it "creates a Baltimore-only development graph with users, district links, legislator links, and votes" do
      expect(OnUserVoteUpdateScoresJob).not_to receive(:perform_later)
      expect(OnLegislatorVoteUpdateScoresJob).not_to receive(:perform_later)

      summary = described_class.run([baltimore, other_locale], user_count: 12, vote_seed: "alpha")

      seeded_users = described_class.seeded_users.order(:id)
      district_score_rows = BillScoreDistrict.where(bill_score: BillScore.where(bill: bills))

      expect(summary).to include(users: 12, created_users: 12, created_addresses: 12)
      expect(summary[:created_user_votes]).to be > 0
      expect(seeded_users.count).to eq(12)
      expect(UserAddress.where(user: seeded_users).count).to eq(12)
      expect(UserDistrict.where(user: seeded_users)).to be_empty
      # @lat: [[seeded-development-users#Synthetic users resolve district coverage through active representatives]]
      expect(
        UserLegislator
          .where(user: seeded_users, active: true)
          .joins(legislator: :district)
          .distinct
          .count("districts.id")
      ).to be > 1
      expect(
        UserLegislator.where(user: seeded_users, active: true).distinct.count(:legislator_id)
      ).to be > 1
      expect(LegislatorVote.where(bill: bills).count).to eq(15)
      expect(UserVote.where(user: seeded_users).count).to be_between(1, 36)
      expect(UserVote.where(bill: other_bill).count).to eq(0)
      expect(seeded_users).to all(be_registered)
      expect(seeded_users.pluck(:registration_status).uniq).to eq(["completed"])
      expect(seeded_users.pluck(:is_registration_complete).uniq).to eq([true])
      expect(BillScore.where(bill: bills).pluck(:for).sum).to be > 0
      expect(district_score_rows.count).to eq(9)
      expect(district_score_rows.pluck(:for).uniq.length).to be > 1
      expect(district_score_rows.pluck(:against).uniq.length).to be > 1
      expect(UserLegislatorTermScore.where(user_legislator: UserLegislator.where(user: seeded_users)).pluck(:count_agreed).sum).to be > 0
      # Score rows point at a legislator_term, not at a legislator, so find the
      # person by joining through the term.
      expect(
        LegislatorDistrictScore
          .joins(:legislator_term)
          .where(legislator_terms: {legislator_id: [council_president.id, district_one_legislator.id]})
          .pluck(:count_agreed).sum
      ).to be > 0
    end

    # @lat: [[seeded-development-users#Seeded users carry numbers no carrier will route]]
    it "gives every seeded user a distinct number in the unassigned 333 area code" do
      described_class.run([baltimore], user_count: 8, vote_seed: "alpha")

      phones = described_class.seeded_users.map(&:phone)

      expect(phones.length).to eq(8)
      expect(phones.uniq.length).to eq(8)
      expect(phones).to all(match(/\A333\d{7}\z/))
    end

    # @lat: [[seeded-development-users#Seeded legislator votes retain their resolved term]]
    it "persists each seeded legislator vote with its resolved term" do
      described_class.run([baltimore], user_count: 0, vote_seed: "alpha")

      seeded_votes = LegislatorVote.where(bill_id: bills.map(&:id), source: "manual").to_a
      terms_by_id = LegislatorTerm.where(id: seeded_votes.map(&:legislator_term_id)).index_by(&:id)

      expect(seeded_votes).not_to be_empty
      expect(seeded_votes).to all(satisfy do |vote|
        vote.legislator_term_id.present? && terms_by_id.fetch(vote.legislator_term_id).legislator_id == vote.legislator_id
      end)
    end

    it "does not overwrite an existing legislator vote when reseeding" do
      existing_vote =
        create(
          :legislator_vote,
          bill: bills.first,
          legislator: mayor,
          support: LegislatorVote::Support::ABSTAIN,
          source: "manual"
        )

      described_class.run([baltimore], user_count: 4, vote_seed: "alpha")

      expect(existing_vote.reload.support).to eq(LegislatorVote::Support::ABSTAIN)
      expect(LegislatorVote.where(bill: bills).count).to eq(15)
    end

    it "replaces only seeded users' votes on rerun and re-randomizes them" do
      described_class.run([baltimore], user_count: 4, vote_seed: "alpha")

      seeded_vote_signature =
        UserVote
          .joins(:user)
          .where(users: {email: ["dev-baltimore-user-001@dev-baltimore.sway.vote", "dev-baltimore-user-002@dev-baltimore.sway.vote", "dev-baltimore-user-003@dev-baltimore.sway.vote", "dev-baltimore-user-004@dev-baltimore.sway.vote"]})
          .order(:user_id, :bill_id)
          .pluck(:user_id, :bill_id, :support)

      outside_user = create(:user, email: "outside@sway.vote", phone: "4105558888", full_name: "Outside User")
      outside_vote = UserVote.create!(user: outside_user, bill: bills.first, support: LegislatorVote::Support::FOR)

      described_class.run([baltimore], user_count: 4, vote_seed: "beta")

      reseeded_vote_signature =
        UserVote
          .joins(:user)
          .where(users: {email: ["dev-baltimore-user-001@dev-baltimore.sway.vote", "dev-baltimore-user-002@dev-baltimore.sway.vote", "dev-baltimore-user-003@dev-baltimore.sway.vote", "dev-baltimore-user-004@dev-baltimore.sway.vote"]})
          .order(:user_id, :bill_id)
          .pluck(:user_id, :bill_id, :support)

      expect(reseeded_vote_signature).not_to eq(seeded_vote_signature)
      expect(outside_vote.reload).to be_present
      expect(UserVote.find_by(id: outside_vote.id)).to eq(outside_vote)
      expect(described_class.seeded_users.count).to eq(4)
      expect(LegislatorVote.where(bill: bills).count).to eq(15)
    end

    it "does nothing when the seeder is disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)

      expect { described_class.run([baltimore], user_count: 3) }
        .not_to change(User, :count)
    end
  end
end
