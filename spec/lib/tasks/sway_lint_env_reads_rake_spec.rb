# frozen_string_literal: true

require "rails_helper"
require "rake"

# @lat: [[env-read-check-design#Why sway_lint_env_reads_rake_spec.rb stubs EnvReadCheck.new for its failure-path examples]]
RSpec.describe "sway:lint:env_reads" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:lint:env_reads")
  end

  before { Rake::Task["sway:lint:env_reads"].reenable }

  it "passes against the real app/ tree, where exactly one read is allowed" do
    expect { Rake::Task["sway:lint:env_reads"].invoke }.not_to raise_error
  end

  it "does not abort when the only offence found is at the allowed path itself" do
    allowed = EnvReadCheck::Offence.new(path: "app/lib/env_secret.rb", line: 10)
    fake_check = instance_double(
      EnvReadCheck,
      offences: [allowed],
      skipped_paths: [],
      allowed_paths: ["app/lib/env_secret.rb"],
      scanned_paths: ["app/lib/env_secret.rb"]
    )
    allow(EnvReadCheck).to receive(:new).and_return(fake_check)

    expect { Rake::Task["sway:lint:env_reads"].invoke }.not_to raise_error
  end

  it "aborts with a nonzero exit when an offence is found outside the allowed path" do
    disallowed = EnvReadCheck::Offence.new(path: "app/controllers/example_controller.rb", line: 3)
    fake_check = instance_double(
      EnvReadCheck,
      offences: [disallowed],
      skipped_paths: [],
      allowed_paths: ["app/lib/env_secret.rb"],
      scanned_paths: ["app/controllers/example_controller.rb", "app/lib/env_secret.rb"]
    )
    allow(EnvReadCheck).to receive(:new).and_return(fake_check)

    expect { Rake::Task["sway:lint:env_reads"].invoke }.to raise_error(SystemExit)
  end

  it "aborts loud (not just skips) when the allowlisted door itself is missing" do
    fake_check = instance_double(EnvReadCheck)
    allow(EnvReadCheck).to receive(:new).and_return(fake_check)
    allow(fake_check).to receive(:offences)
      .and_raise(EnvReadCheck::MissingAllowlistedPathError, "app/lib/env_secret.rb is missing")

    expect { Rake::Task["sway:lint:env_reads"].invoke }.to raise_error(SystemExit)
  end
end
