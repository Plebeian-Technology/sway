# frozen_string_literal: true

require "rails_helper"

# @lat: [[score-updater-service-design#Why each score family uses a different scope and a different term]]
RSpec.describe RecomputeDistrictScoresJob, type: :job do
  it "recomputes the district scores for the bills and the legislators it is given" do
    sway_locale = create(:sway_locale)
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)
    create(:legislator_term, legislator:, district:)
    allow(ScoreRecomputeService).to receive(:recompute_district_scores!)

    described_class.new.perform([11, 12], [legislator.id])

    expect(ScoreRecomputeService).to have_received(:recompute_district_scores!).with([11, 12], legislators: [legislator])
  end

  it "skips a legislator that no longer exists" do
    allow(ScoreRecomputeService).to receive(:recompute_district_scores!)

    described_class.new.perform([11], [0])

    expect(ScoreRecomputeService).to have_received(:recompute_district_scores!).with([11], legislators: [])
  end

  it "runs on the background queue" do
    expect(described_class.new.queue_name).to eq("background")
  end
end
