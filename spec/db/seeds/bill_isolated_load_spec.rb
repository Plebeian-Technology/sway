# frozen_string_literal: true

require "rails_helper"
require "open3"
require Rails.root.join("db", "seeds", "models", "bill")

# @lat: [[seed-bill-pipeline-run-guard#How the isolated-load regression is tested]]
RSpec.describe "db/seeds/models/bill.rb isolated load" do
  it "loads without LegislationPipelineRun being autoloaded" do
    script = <<~RUBY
      $LOAD_PATH.unshift #{Rails.root.to_s.inspect}
      require "active_support"
      require "active_support/core_ext"
      module Rails
        def self.env
          ActiveSupport::StringInquirer.new("development")
        end
        def self.logger
          require "logger"
          Logger.new(IO::NULL)
        end
      end
      module Seedable; end
      require_relative #{Rails.root.join("db", "seeds", "models", "bill").to_s.inspect}
      # If we got here, the class body did not reach autoloaded constants.
      print "ok"
    RUBY

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "--disable-gems",
      "-e", script
    )

    expect(status.success?).to be(true),
      "subprocess failed: stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    expect(stderr).not_to match(/NameError.*LegislationPipelineRun/),
      "Regression: SeedBill referenced LegislationPipelineRun at class-load time. " \
      "Move the lookup into a method body (lazy eval) so Zeitwerk has booted by call time."
    expect(stdout).to eq("ok")
  end

  it "memoizes terminal_success_for_seed on the first call" do
    # Smoke test inside the full rails_helper boot: the lazy accessor should
    # resolve to the model's constant plus ["partial"], then cache the result.
    expected = LegislationPipelineRun::TERMINAL_SUCCESS_STATUSES + %w[partial]
    SeedBill.instance_variable_set(:@terminal_success_for_seed, nil)
    first = SeedBill.send(:terminal_success_for_seed)
    second = SeedBill.send(:terminal_success_for_seed)
    expect(first).to eq(expected)
    expect(first).to be_frozen
    expect(second).to equal(first) # cached, so it is the very same object
  end
end
