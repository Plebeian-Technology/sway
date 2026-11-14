# frozen_string_literal: true

require "rails_helper"
require "rake"
require Rails.root.join("db", "seeds", "models", "sway_locale")

RSpec.describe "sway:locales:verify_registration" do
  let(:task) { Rake::Task["sway:locales:verify_registration"] }
  let(:annapolis_name) { "annapolis-maryland-united_states" }
  let(:baltimore_name) { "baltimore-maryland-united_states" }

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:locales:verify_registration")
  end

  before do
    task.reenable
    SeedSwayLocale.run
    allow_any_instance_of(SwayRegistrationService).to receive(:call).and_return([]) # rubocop:disable RSpec/AnyInstance
  end

  def run_task
    task.invoke
    nil
  rescue SystemExit => e
    e.status
  end

  def record_counts
    [User.count, Address.count, UserLegislator.count]
  end

  it "prints a line for every declared locale and leaves the database unchanged" do
    counts = record_counts
    status = nil

    expect { status = run_task }.to output(
      a_string_including(*SwayLocale::JurisdictionRulesRegistry.declared_locale_names)
    ).to_stdout

    expect(status).to be_nil
    expect(record_counts).to eq(counts)
  end

  it "exits 1, logs the exception with the locale name and still rolls back when a locale raises" do
    allow_any_instance_of(SwayRegistrationService).to receive(:call) do |service| # rubocop:disable RSpec/AnyInstance
      raise "roster lookup failed" if service.sway_locale.name == annapolis_name

      []
    end
    allow(SwayLogging).to receive(:log_exception)
    counts = record_counts
    status = nil

    expect { status = run_task }.to output.to_stdout.and output(/#{annapolis_name}/).to_stderr

    expect(status).to eq(1)
    expect(SwayLogging).to have_received(:log_exception).with(
      "sway_locales.verify_registration_failed",
      exception: an_instance_of(RuntimeError).and(having_attributes(message: "roster lookup failed")),
      sway_locale: annapolis_name
    )
    expect(record_counts).to eq(counts)
  end

  it "exits 1 and names the locale when a run skips a term" do
    allow_any_instance_of(SwayRegistrationService).to receive(:skipped_resolution_errors) do |service| # rubocop:disable RSpec/AnyInstance
      (service.sway_locale.name == baltimore_name) ? [Seats::UnresolvedSeatError.new("no seat")] : []
    end
    allow(SwayLogging).to receive(:log_exception)
    status = nil

    expect { status = run_task }.to output.to_stdout.and output(/#{baltimore_name}/).to_stderr

    expect(status).to eq(1)
    expect(SwayLogging).to have_received(:log_exception).with(
      "sway_locales.verify_registration_failed",
      exception: an_instance_of(Seats::UnresolvedSeatError),
      sway_locale: baltimore_name
    )
  end

  it "exits 1 and names the declared locales that no sample address reaches" do
    SwayLocale.where(city: ["baltimore", "annapolis"]).update_all(sample_street: nil)
    status = nil

    expect { status = run_task }.to output(
      a_string_including("maryland-maryland-united_states", "congress-congress-united_states")
    ).to_stderr

    expect(status).to eq(1)
  end
end
