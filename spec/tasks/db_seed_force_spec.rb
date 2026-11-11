# frozen_string_literal: true

require "rails_helper"
require "rake"
require Rails.root.join("db", "seeds", "models", "bill")
require Rails.root.join("db", "seeds", "models", "development_user_graph")

RSpec.describe "db:seed:force rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:seed:force")
  end

  before do
    Rake::Task["db:seed:force"].reenable
  end

  it "invokes SeedSwayLocale.run with force: true, passes its return value to SeedLegislator.run, SeedBill.run, and SeedDevelopmentUserGraph.run" do
    locales = [instance_double(SwayLocale)]

    expect(SeedSwayLocale).to receive(:run).with(force: true).and_return(locales)
    expect(SeedLegislator).to receive(:run).with(locales, force: true)
    expect(SeedBill).to receive(:run).with(locales, force: true)
    expect(SeedDevelopmentUserGraph).to receive(:run).with(locales).and_return(nil)

    Rake::Task["db:seed:force"].invoke
  end

  it "still completes when SeedBill raises Faraday::ConnectionFailed (service unreachable)" do
    empty_locales = [] #: Array[untyped]
    allow(SeedSwayLocale).to receive(:run).with(force: true).and_return(empty_locales)
    allow(SeedLegislator).to receive(:run)
    allow(SeedBill).to receive(:run).and_raise(Faraday::ConnectionFailed, "connection refused")

    expect(Rails.logger).to receive(:warn).with(/SeedBill skipped.*db:seed:bills:force/)

    expect { Rake::Task["db:seed:force"].invoke }.not_to raise_error
  end

  it "still completes when SeedBill raises ServiceUnreachableError (assert_service_reachable! path)" do
    empty_locales = [] #: Array[untyped]
    allow(SeedSwayLocale).to receive(:run).with(force: true).and_return(empty_locales)
    allow(SeedLegislator).to receive(:run)
    allow(SeedBill).to receive(:run).and_raise(
      SeedBill::ServiceUnreachableError,
      "Legislation service not reachable at http://localhost:5555"
    )

    expect(Rails.logger).to receive(:warn).with(/SeedBill skipped.*db:seed:bills:force/)

    expect { Rake::Task["db:seed:force"].invoke }.not_to raise_error
  end

  it "re-raises unrelated RuntimeError from SeedBill (defensive boundary)" do
    # The rake task no longer decides what to ignore by matching words inside a
    # RuntimeError's message. An unrelated RuntimeError — a bug partway through
    # the import, say — must travel up, not get mistaken for a 'not reachable'
    # message and swallowed.
    empty_locales = [] #: Array[untyped]
    allow(SeedSwayLocale).to receive(:run).with(force: true).and_return(empty_locales)
    allow(SeedLegislator).to receive(:run)
    allow(SeedBill).to receive(:run).and_raise(RuntimeError, "something completely different exploded")

    expect { Rake::Task["db:seed:force"].invoke }.to raise_error(RuntimeError, /something completely different/)
  end
end
