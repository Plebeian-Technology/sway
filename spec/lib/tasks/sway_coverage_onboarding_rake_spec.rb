# frozen_string_literal: true

require "rails_helper"
require "rake"

# @lat: [[verification-gates#Onboarding coverage gate]]
RSpec.describe "sway:coverage:onboarding" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:coverage:onboarding")
  end

  before { Rake::Task["sway:coverage:onboarding"].reenable }

  it "prints each file's coverage and passes when no file is under its floor" do
    fake_check = instance_double(OnboardingCoverageCheck, report: ["app/models/user.rb: line 90.0% (floor 90.0%), branch 80.0% (floor 80.0%)"], failures: [])
    allow(OnboardingCoverageCheck).to receive(:new).and_return(fake_check)

    expect { Rake::Task["sway:coverage:onboarding"].invoke }
      .to output(%r{app/models/user\.rb: line 90\.0%}).to_stdout
  end

  it "aborts with a nonzero exit naming the file when a file is under its floor" do
    fake_check = instance_double(OnboardingCoverageCheck, report: [], failures: ["app/models/user.rb: line coverage 80.0% is below its floor of 90.0%"])
    allow(OnboardingCoverageCheck).to receive(:new).and_return(fake_check)

    expect { Rake::Task["sway:coverage:onboarding"].invoke }
      .to raise_error(SystemExit)
      .and output(%r{app/models/user\.rb: line coverage 80\.0% is below its floor}).to_stderr
  end

  it "merges only the worker results written at or after the since argument" do
    fake_check = instance_double(OnboardingCoverageCheck, report: [], failures: [])
    allow(OnboardingCoverageCheck).to receive(:new).and_return(fake_check)

    Rake::Task["sway:coverage:onboarding"].invoke("1700000000")

    expect(OnboardingCoverageCheck).to have_received(:new).with(hash_including(since: 1_700_000_000))
  end
end
