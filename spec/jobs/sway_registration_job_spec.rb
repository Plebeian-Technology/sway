require "rails_helper"

RSpec.describe SwayRegistrationJob, type: :job do
  include ActiveJob::TestHelper

  empty_array = [] #: Array[untyped]

  let(:user_fixture) { create(:user, is_registration_complete: false) }
  let(:address) { create(:address) }
  let(:sway_locale_fixture) { create(:sway_locale) }

  describe "#perform" do
    it "enqueues the job with expected args (including invited_by_id kwarg)" do
      expect {
        described_class.perform_later(
          user_fixture.id,
          address.id,
          sway_locale_fixture.id,
          invited_by_id: nil
        )
      }.to have_enqueued_job(described_class).with(
        user_fixture.id,
        address.id,
        sway_locale_fixture.id,
        invited_by_id: nil
      )
    end

    it "completes when an active pairing exists after SwayRegistrationService runs" do
      # Fake the service so the job's success path runs without seeding a full
      # set of legislators and districts. What is under test is that the job
      # calls the service and then moves the user to the next state.
      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_return(empty_array)

      create(:user_legislator, user: user_fixture)
      user_fixture.start_processing!

      perform_enqueued_jobs do
        described_class.perform_later(
          user_fixture.id,
          address.id,
          sway_locale_fixture.id,
          invited_by_id: nil
        )
      end

      expect(user_fixture.reload.registration_status).to eq("completed")
    end

    it "marks an empty result failed with safe no-representatives metadata" do
      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_return(empty_array)
      user_fixture.start_processing!

      perform_enqueued_jobs do
        described_class.perform_later(
          user_fixture.id,
          address.id,
          sway_locale_fixture.id,
          invited_by_id: nil
        )
      end

      user_fixture.reload
      expect(user_fixture.registration_status).to eq("failed")
      expect(user_fixture.is_registration_complete).to be(false)
      failure_event = user_fixture.registration_funnel_events.geocoding_failed.last
      expect(failure_event.metadata).to include("reason" => "no_representatives")
    end

    # A brief outage upstream must lead to a retry, not to a registration that
    # fails for good on the first hiccup. perform_enqueued_jobs runs the retries
    # right here, so the whole sequence happens inside the test.
    it "retries a transient error and completes when a later attempt succeeds" do
      call_count = 0
      allow_any_instance_of(SwayRegistrationService).to receive(:call) do
        call_count += 1
        raise Faraday::TimeoutError if call_count == 1
        empty_array
      end
      create(:user_legislator, user: user_fixture)
      user_fixture.start_processing!

      perform_enqueued_jobs do
        described_class.perform_later(
          user_fixture.id, address.id, sway_locale_fixture.id, invited_by_id: nil
        )
      end

      expect(user_fixture.reload.registration_status).to eq("completed")
    end

    it "marks the user failed once transient retries are exhausted" do
      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_raise(Faraday::TimeoutError)
      user_fixture.start_processing!

      perform_enqueued_jobs do
        described_class.perform_later(
          user_fixture.id, address.id, sway_locale_fixture.id, invited_by_id: nil
        )
      end

      expect(user_fixture.reload.registration_status).to eq("failed")
    end

    it "surfaces the original error, not RecordNotFound, when the user is deleted mid-run" do
      allow_any_instance_of(SwayRegistrationService).to receive(:call) do
        User.find(user_fixture.id).destroy!
        raise StandardError, "original error"
      end

      expect {
        described_class.new(
          user_fixture.id, address.id, sway_locale_fixture.id, invited_by_id: nil
        ).perform_now
      }.to raise_error(StandardError, "original error")
    end

    it "transitions user to :failed when the service raises" do
      allow_any_instance_of(SwayRegistrationService).to receive(:call).and_raise(
        StandardError,
        "boom"
      )

      # The job catches the error and calls mark_failed! only when the user is in
      # :processing.
      user_fixture.start_processing!

      # ActiveJob's test adapter re-raises a job failure wrapped in
      # Minitest::UnexpectedError, which is not a StandardError. Catching
      # Exception keeps this test from depending on that wrapper class; the real
      # check is the state change asserted afterwards.
      begin
        perform_enqueued_jobs do
          described_class.perform_later(
            user_fixture.id,
            address.id,
            sway_locale_fixture.id,
            invited_by_id: nil
          )
        end
      rescue Exception # rubocop:disable Lint/RescueException
        # expected
      end

      expect(user_fixture.reload.registration_status).to eq("failed")
    end
  end
end
