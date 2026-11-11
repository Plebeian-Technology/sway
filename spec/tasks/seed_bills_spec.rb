# frozen_string_literal: true

require "rails_helper"
require "rake"
require Rails.root.join("db", "seeds", "models", "bill")
require Rails.root.join("db", "seeds", "models", "development_user_graph")

RSpec.describe "db:seed:bills rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:seed:bills")
  end

  before do
    Rake::Task["db:seed:bills"].reenable
  end

  let!(:baltimore) do
    create(
      :sway_locale,
      city: "baltimore",
      state: "maryland",
      country: "United States"
    )
  end
  let!(:district) { create(:district, sway_locale: baltimore, name: "MD0") }
  let!(:council_president) do
    create(
      :legislator,
      district: district,
      title: "Council President",
      external_id: "seed-bills-council-president"
    )
  end

  it "runs the development user graph seeder once Baltimore bills exist" do
    create(
      :bill,
      sway_locale: baltimore,
      legislator: council_president,
      external_id: "seed-bills-existing",
      scheduled_release_date_utc: nil
    )

    expect(SeedBill).to receive(:run).with([baltimore], force: false, refresh: false).and_return(["seed-bills-existing"])
    expect(SeedDevelopmentUserGraph).to receive(:run).with([baltimore]).and_return(users: 200)

    Rake::Task["db:seed:bills"].invoke
  end

  it "skips the development user graph seeder when Baltimore still has no bills" do
    expect(SeedBill).to receive(:run).with([baltimore], force: false, refresh: false).and_return(nil)
    expect(SeedDevelopmentUserGraph).to receive(:run).with([baltimore]).and_return(nil)

    Rake::Task["db:seed:bills"].invoke
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#Seeding trims each locale back to a fixed number of bills]]
  it "trims to the MAX_SEEDED_BILLS most-recent bills after the pipeline over-creates" do
    allow(SeedBill).to receive(:run_pipeline_synchronously!) do
      15.times do |i|
        create(
          :bill,
          sway_locale: baltimore,
          legislator: council_president,
          external_id: "cap-#{i}",
          introduced_date_time_utc: Time.utc(2026, 1, 1) + i.days,
          scheduled_release_date_utc: nil
        )
      end
    end

    SeedBill.run([baltimore], force: true, refresh: false)

    kept = Bill.where(sway_locale: baltimore).pluck(:external_id)
    expect(kept.size).to eq(SeedBill::MAX_SEEDED_BILLS)
    # the survivors are the 10 newest by introduced_date (cap-5 through cap-14)
    expect(kept).to match_array((5..14).map { |i| "cap-#{i}" })
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#Seeding trims each locale back to a fixed number of bills]]
  it "trims over-cap bills that carry FK'd rows (e.g. a user_vote) without raising" do
    voter = nil
    allow(SeedBill).to receive(:run_pipeline_synchronously!) do
      15.times do |i|
        create(
          :bill,
          sway_locale: baltimore,
          legislator: council_president,
          external_id: "cap-#{i}",
          introduced_date_time_utc: Time.utc(2026, 1, 1) + i.days,
          scheduled_release_date_utc: nil
        )
      end
      voter = create(:user)
      # cap-0 is the oldest, so it is certainly past the 10-bill cap and is cut.
      create(:user_vote, user: voter, bill: Bill.find_by!(external_id: "cap-0"))
    end

    expect { SeedBill.run([baltimore], force: true, refresh: false) }.not_to raise_error

    expect(Bill.where(sway_locale: baltimore).count).to eq(SeedBill::MAX_SEEDED_BILLS)
    expect(Bill.find_by(external_id: "cap-0")).to be_nil
    expect(UserVote.where(user: voter).count).to eq(0)
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#Seeding trims each locale back to a fixed number of bills]]
  describe ".resolve_max_seeded_bills" do
    it "falls back to the default for non-positive or garbage values" do
      expect(SeedBill.resolve_max_seeded_bills("0")).to eq(SeedBill::DEFAULT_MAX_SEEDED_BILLS)
      expect(SeedBill.resolve_max_seeded_bills("-5")).to eq(SeedBill::DEFAULT_MAX_SEEDED_BILLS)
      expect(SeedBill.resolve_max_seeded_bills("abc")).to eq(SeedBill::DEFAULT_MAX_SEEDED_BILLS)
    end

    it "honors a positive override" do
      expect(SeedBill.resolve_max_seeded_bills("25")).to eq(25)
    end
  end

  describe "SeedBill pipeline run locale propagation" do
    it "forwards the supplied SwayLocale to LegislationPipelineRunService and creates a run" do
      allow(RunLegislationPipelineJob).to receive(:perform_now) do |run_id, **|
        LegislationPipelineRun.find(run_id).update!(status: "completed")
      end

      expect {
        SeedBill.send(:run_pipeline_synchronously!, baltimore, download_missing_assets: false)
      }.not_to raise_error

      run = LegislationPipelineRun.last!
      expect(run.sway_locale).to eq(baltimore)
      expect(run.download_missing_assets).to be(false)
    end

    it "forwards the locale when executing SeedBill.run without stubbing run_pipeline_synchronously!" do
      allow(RunLegislationPipelineJob).to receive(:perform_now) do |run_id, **|
        LegislationPipelineRun.find(run_id).update!(status: "completed")
      end

      expect {
        SeedBill.run([baltimore], force: true, refresh: false)
      }.not_to raise_error

      run = LegislationPipelineRun.last!
      expect(run.sway_locale).to eq(baltimore)
    end
  end
end
