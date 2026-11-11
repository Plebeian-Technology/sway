# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "rake sway:lint:admin_guards" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:lint:admin_guards")
  end

  it "passes today (all admin controllers carry the before_action)" do
    Rake::Task["sway:lint:admin_guards"].reenable
    expect { Rake::Task["sway:lint:admin_guards"].invoke }.not_to raise_error
  end

  it "flags a controller missing the before_action (failure path)" do
    # @lat: [[admin-guards-lint-spec-design#Why admin_guards_lint_spec.rb's failure-path example fakes Pathname.read]]
    allow_any_instance_of(Pathname).to receive(:read).and_wrap_original do |original, *args|
      # @type var original: Method
      if original.receiver.to_s.end_with?("bills_controller.rb")
        "class BillsController < ApplicationController; end"
      else
        original.call(*args)
      end
    end
    Rake::Task["sway:lint:admin_guards"].reenable
    expect { Rake::Task["sway:lint:admin_guards"].invoke }.to raise_error(SystemExit)
  end

  it "verifies CLAUDE.md contains no hardcoded controller count in its admin guards note" do
    enforcement_line = Rails.root.join("CLAUDE.md").read.lines.find do |line|
      line.include?("bundle exec rake sway:lint:admin_guards")
    end
    expect(enforcement_line).not_to be_nil
    expect(enforcement_line).not_to match(/\b\d+\b/)
  end
end
