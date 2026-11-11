# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "sway:bills:archive_previous_sessions" do
  let(:task) { Rake::Task["sway:bills:archive_previous_sessions"] }
  let(:locale) { create(:sway_locale) }
  let!(:session) do
    create(:legislative_session, sway_locale: locale, active: true,
      start_date: Date.current.beginning_of_year, end_date: Date.current.end_of_year)
  end
  let!(:bill) do
    create(:bill, sway_locale: locale, legislative_session: nil,
      scheduled_release_date_utc: nil, introduced_date_time_utc: 2.years.ago)
  end

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:bills:archive_previous_sessions")
  end

  before { task.reenable }

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Command preview and apply]]
  it "previews by default and archives only with the apply argument" do
    expect { task.invoke(locale.name) }.to output(/Preview: 1 bill.*#{bill.external_id}/m).to_stdout
    expect(bill.reload.archived_at).to be_nil

    task.reenable
    expect { task.invoke(locale.name, "apply") }.to output(/Archived 1 bill/).to_stdout
    expect(Bill.unscoped.find(bill.id).archived_at).to be_present
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Command input validation]]
  it "rejects missing or unknown locales and mistyped apply arguments" do
    expect { task.invoke }.to raise_error(ArgumentError, /locale/)
    task.reenable
    expect { task.invoke("unknown-locale") }.to raise_error(ArgumentError, /locale/)
    task.reenable
    expect { task.invoke(locale.name, "aply") }.to raise_error(ArgumentError, /apply/)
    expect(bill.reload.archived_at).to be_nil
  end
end
