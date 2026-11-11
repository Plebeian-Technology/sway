# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Batch summarisation#One settle shared by the job and the ingest]]
RSpec.describe SummaryRunSettle do
  let(:sway_locale) { SwayLocale.find_by(city: "baltimore") || create(:sway_locale, :baltimore) }
  let(:bill) { create(:bill, external_id: "SRS-1", sway_locale: sway_locale, scheduled_release_date_utc: 710.days.ago) }
  let(:provisioning) { create(:bill_llm_provisioning, :generating, bill: bill) }

  it "moves a generating row to completed" do
    described_class.completed!(bill, provisioning)

    expect(provisioning.reload.generation_status).to eq("completed")
  end

  it "leaves a row that is not generating alone" do
    settled = create(:bill_llm_provisioning, :completed, bill: create(:bill, external_id: "SRS-2",
      sway_locale: sway_locale, scheduled_release_date_utc: 711.days.ago))

    expect { described_class.completed!(settled.bill, settled) }
      .not_to change { settled.reload.generation_status }
  end

  it "clears a stale generation_error only when asked to" do
    provisioning.update_columns(generation_error: "stale")

    described_class.completed!(bill, provisioning, clear_generation_error: true)

    expect(provisioning.reload.generation_error).to be_nil
  end

  it "keeps the generation_error when not asked to clear it" do
    provisioning.update_columns(generation_error: "positions call failed: boom")

    described_class.completed!(bill, provisioning)

    expect(provisioning.reload.generation_error).to eq("positions call failed: boom")
  end

  it "recomputes the bill's score by default" do
    provisioning

    expect { described_class.completed!(bill, provisioning) }
      .to have_enqueued_job(RecomputeBillInterestingScoreJob).with(bill.id)
  end

  it "does not recompute when the caller can prove nothing was bought" do
    provisioning

    expect { described_class.completed!(bill, provisioning, recompute_score: false) }
      .not_to have_enqueued_job(RecomputeBillInterestingScoreJob)
  end

  it "does not recompute a row it did not settle" do
    settled = create(:bill_llm_provisioning, :completed, bill: create(:bill, external_id: "SRS-3",
      sway_locale: sway_locale, scheduled_release_date_utc: 712.days.ago))

    expect { described_class.completed!(settled.bill, settled) }
      .not_to have_enqueued_job(RecomputeBillInterestingScoreJob)
  end
end
