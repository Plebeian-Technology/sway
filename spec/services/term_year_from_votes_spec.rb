# frozen_string_literal: true

require "rails_helper"

# @lat: [[current-legislator-term#Which cycle a backfilled term belongs to]]
RSpec.describe TermYearFromVotes do
  let(:baltimore_locale) do
    create(:sway_locale, city: "baltimore", state: "maryland", country: "United States")
  end
  let(:congress_locale) do
    create(:sway_locale, city: "congress", state: "congress", country: "United States")
  end

  # Baltimore's 2020 term runs 2020-12-10 to the 2024 convening on
  # 2024-12-05. Each bill needs its own scheduled_release_date_utc, since
  # two bills in one locale collide unless dates differ.
  def baltimore_legislator_voting_on(*dates, created_on: Time.zone.local(2024, 5, 6))
    legislator = create(:legislator, sway_locale: baltimore_locale)
    legislator.update_columns(created_at: created_on)
    dates.each_with_index do |date, index|
      bill = create(:bill, sway_locale: baltimore_locale,
        house_vote_date_time_utc: date,
        scheduled_release_date_utc: Time.zone.local(2030, 1, 1) + index.days)
      create(:legislator_vote, legislator:, bill:)
    end
    legislator
  end

  it "reads the 2020 cycle off votes cast before the 2024 handover" do
    legislator = baltimore_legislator_voting_on(
      Time.zone.local(2024, 2, 26), Time.zone.local(2024, 12, 3)
    )

    expect(described_class.new(legislator).call).to eq(2020)
  end

  it "reads the 2024 cycle off votes cast after the handover" do
    legislator = baltimore_legislator_voting_on(
      Time.zone.local(2025, 2, 24), Time.zone.local(2026, 4, 1)
    )

    expect(described_class.new(legislator).call).to eq(2024)
  end

  # This is the case the production defect turned on. The row was last seeded in
  # 2026, which is what the old backfill read, but every vote on it was cast in
  # the 2020 cycle. The votes win.
  it "ignores last_seeded_at falling in a later cycle than the one served" do
    legislator = baltimore_legislator_voting_on(Time.zone.local(2024, 3, 4))
    legislator.update_columns(last_seeded_at: Time.zone.local(2026, 4, 30))

    expect(described_class.new(legislator).call).to eq(2020)
  end

  describe "when the votes cannot settle it" do
    it "returns nil for a legislator with no votes" do
      legislator = create(:legislator, sway_locale: baltimore_locale)

      expect(described_class.new(legislator).call).to be_nil
    end

    # Votes either side of a handover mean two terms, which one term year
    # cannot describe. Saying nothing beats saying something wrong.
    it "returns nil when votes straddle a handover" do
      legislator = baltimore_legislator_voting_on(
        Time.zone.local(2024, 6, 1), Time.zone.local(2025, 6, 1)
      )

      expect(described_class.new(legislator).call).to be_nil
    end

    # Found by replaying against the production snapshot: phase 65 merged
    # duplicate identities and moved losing rows' votes onto the survivor,
    # so a row can carry votes cast before it existed.
    it "returns nil when the cycle ended before the row was even created" do
      legislator = create(:legislator, sway_locale: congress_locale)
      bill = create(:bill, sway_locale: congress_locale,
        house_vote_date_time_utc: Time.zone.local(2024, 6, 1))
      create(:legislator_vote, legislator:, bill:)
      legislator.update_columns(created_at: Time.zone.local(2026, 7, 23))

      expect(described_class.new(legislator).call).to be_nil
    end

    it "returns nil when a bill carries no vote date at all" do
      legislator = create(:legislator, sway_locale: baltimore_locale)
      bill = create(:bill, sway_locale: baltimore_locale,
        house_vote_date_time_utc: nil, senate_vote_date_time_utc: nil)
      create(:legislator_vote, legislator:, bill:)

      expect(described_class.new(legislator).call).to be_nil
    end
  end

  it "uses Congress's two-year cycle, not a four-year one" do
    legislator = create(:legislator, sway_locale: congress_locale)
    bill = create(:bill, sway_locale: congress_locale,
      house_vote_date_time_utc: Time.zone.local(2024, 6, 1))
    create(:legislator_vote, legislator:, bill:)
    # Created inside the 2023 cycle, which runs to 2025-01-03, so these really
    # are this row's own votes.
    legislator.update_columns(created_at: Time.zone.local(2024, 5, 6))

    expect(described_class.new(legislator).call).to eq(2023)
  end
end
