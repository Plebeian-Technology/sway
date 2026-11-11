# frozen_string_literal: true

require "rails_helper"

# @lat: [[reader-control-browser-tests#Reader control browser tests]]
RSpec.describe "Guest Preview Sway vote", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale, :congress) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) do
    create(
      :bill,
      :bill_of_the_month,
      sway_locale: sway_locale,
      legislator: legislator,
      title: "Monthly Preview Test Bill"
    )
  end

  # @lat: [[reader-control-browser-tests#Reader control browser tests#Guest preview#Guest Preview Sway reaches provisional voting]]
  it "lets a signed-out reader preview the monthly bill and save a provisional vote" do
    bill
    users_before = User.order(:id).pluck(:id)
    user_votes_before = UserVote.order(:id).pluck(:id)

    visit "/?sway_locale_id=#{sway_locale.id}"
    expect(page).to have_link("Preview Sway", wait: 10)
    click_link("Preview Sway")

    expect(page).to have_current_path("/bill_of_the_month", ignore_query: true, wait: 20)
    expect(page).to have_text(:visible, bill.title, wait: 20)
    score_snapshot = lambda do
      {
        bill_scores: BillScore.where(bill_id: bill.id).order(:id).pluck(:id, :for, :against),
        district_scores: BillScoreDistrict.joins(:bill_score)
          .where(bill_scores: {bill_id: bill.id})
          .order(:id)
          .pluck(:id, :for, :against),
        official_votes: LegislatorVote.where(bill_id: bill.id).order(:id).pluck(:id, :support)
      }
    end
    scores_before = score_snapshot.call

    click_button("For", match: :first)

    modal = find("[data-testid='provisional-registration-modal']", visible: :visible, wait: 20)
    within(modal) do
      expect(page).to have_text(:visible, "Complete quick registration", wait: 10)
    end

    page.refresh
    expect(page).to have_text(:visible, bill.title, wait: 20)
    banner = find("[data-testid='provisional-vote-banner']", visible: :visible, wait: 20)
    within(banner) do
      expect(page).to have_text(:visible, "Pending constituent verification — not yet included in official tallies.")
      expect(page).to have_button("Complete registration")
    end

    expect(User.order(:id).pluck(:id)).to eq(users_before)
    expect(UserVote.order(:id).pluck(:id)).to eq(user_votes_before)
    expect(score_snapshot.call).to eq(scores_before)
  end
end
