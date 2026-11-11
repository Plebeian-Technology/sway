# frozen_string_literal: true

require "rails_helper"
require "rake"

# @lat: [[assign-new-user-legislators-task-safety#Why sway:assign_new_user_legislators asks for confirmation, one user at a time]]
RSpec.describe "sway:assign_new_user_legislators rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:assign_new_user_legislators")
  end

  before do
    Rake::Task["sway:assign_new_user_legislators"].reenable
  end

  around do |example|
    previous = ENV["CONFIRM_ASSIGN_NEW_USER_LEGISLATORS"]
    begin
      example.run
    ensure
      if previous.nil?
        ENV.delete("CONFIRM_ASSIGN_NEW_USER_LEGISLATORS")
      else
        ENV["CONFIRM_ASSIGN_NEW_USER_LEGISLATORS"] = previous
      end
    end
  end

  it "aborts (SystemExit) and deactivates nothing without CONFIRM_ASSIGN_NEW_USER_LEGISLATORS=1" do
    ENV.delete("CONFIRM_ASSIGN_NEW_USER_LEGISLATORS")
    user = create(:user)
    user_legislator = create(:user_legislator, user: user)

    expect {
      Rake::Task["sway:assign_new_user_legislators"].invoke
    }.to raise_error(SystemExit)

    expect(user_legislator.reload.active).to be(true)
  end

  it "with CONFIRM=1, a per-user external-API failure does not stop other users from being processed" do
    ENV["CONFIRM_ASSIGN_NEW_USER_LEGISLATORS"] = "1"

    sway_locale = create(:sway_locale)
    user_a = create(:user)
    user_b = create(:user)
    create(:user_legislator, user: user_a)
    create(:user_legislator, user: user_b)

    # Avoid geocoding: every user reports the same locale so the inner loop runs.
    allow_any_instance_of(User).to receive(:sway_locales).and_return([sway_locale])

    service_a = instance_double(SwayRegistrationService)
    service_b = instance_double(SwayRegistrationService)
    # Two ActiveRecord objects count as equal when the class and id match, so
    # passing the record here also matches the fresh copy find_each loads.
    allow(SwayRegistrationService).to receive(:new)
      .with(user_a, any_args).and_return(service_a)
    allow(SwayRegistrationService).to receive(:new)
      .with(user_b, any_args).and_return(service_b)
    # user_a has the lower id, so find_each reaches it first. It fails, and
    # user_b must still be processed.
    allow(service_a).to receive(:create_user_legislators).and_raise(StandardError, "geocode failed")
    allow(service_b).to receive(:create_user_legislators)

    expect {
      Rake::Task["sway:assign_new_user_legislators"].invoke
    }.not_to raise_error

    # The rescue kept user_a's failure to itself, and user_b was still
    # reassigned. The old design — switch everyone off, then let the loop die on
    # the first error — would have skipped user_b.
    expect(service_b).to have_received(:create_user_legislators)
  end
end
