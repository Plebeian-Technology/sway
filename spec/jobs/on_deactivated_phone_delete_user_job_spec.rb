require "rails_helper"

RSpec.describe OnDeactivatedPhoneDeleteUserJob, type: :job do
  include_context "Setup"

  describe "the deactivation job is run" do
    context "a list of phone  numbers has been received" do
      it "destroys the users with inactive phone numbers and revokes their devices" do
        _sway_locale, user = setup
        device = UserDevice.create!(user: user, platform: "ios", last_seen_at: Time.current)

        job = OnDeactivatedPhoneDeleteUserJob.new
        allow(job).to receive(:deactivated_phones).and_return([user.phone])
        allow(job).to receive(:perform).and_call_original
        expect_any_instance_of(User).to receive(:revoke_all_devices!).and_call_original
        job.perform

        expect(User.find_by(id: user.id)).to be_nil
        expect(UserDevice.find_by(id: device.id)).to be_nil
      end

      it "does not destroy a user when their phone is not in the list" do
        _sway_locale, user = setup

        job = OnDeactivatedPhoneDeleteUserJob.new
        allow(job).to receive(:deactivated_phones).and_return(["1237779999"])
        allow(job).to receive(:perform).and_call_original
        job.perform

        expect(User.find_by(id: user.id)).to_not be_nil
      end

      # @lat: [[on-deactivated-phone-delete-user-job-design#Why a failed destroy reports to Sentry directly]]
      it "alerts Sentry when a user's destroy fails in production" do
        _sway_locale, user = setup

        job = OnDeactivatedPhoneDeleteUserJob.new
        allow(job).to receive(:deactivated_phones).and_return([user.phone])
        allow_any_instance_of(User).to receive(:destroy).and_return(false)
        allow(Rails.env).to receive(:production?).and_return(true)

        # @lat: [[error-reporting-in-tests#Why Sentry's methods are watched rather than the constant replaced]]
        expect(Sentry).to receive(:capture_message).with(/Failed to destroy user #{user.id}/)

        job.perform

        expect(User.find_by(id: user.id)).not_to be_nil # destroy was stubbed false
      end

      # @lat: [[on-deactivated-phone-delete-user-job-design#Why batching uses compact + each_slice, not in_groups_of]]
      it "spares a NULL-phone user when the batch is nil-padded" do
        _sway_locale, user_a = setup
        user_b = create(:user)
        user_b.update_column(:phone, nil)

        job = OnDeactivatedPhoneDeleteUserJob.new
        allow(job).to receive(:deactivated_phones).and_return([user_a.phone])
        job.perform

        expect(User.find_by(id: user_a.id)).to be_nil
        expect(User.find_by(id: user_b.id)).not_to be_nil
      end
    end
  end

  describe "#deactivated_phones parsing" do
    it "normalizes E.164 (+1410...) and 10-digit (+410... / 410...) phones to 10 digits and drops non-phone lines" do
      job = OnDeactivatedPhoneDeleteUserJob.new
      allow(job).to receive(:deactivation_url).and_return(double(redirect_to: "https://twilio.test/deactivations"))
      allow(Faraday).to receive(:get)
        .with("https://twilio.test/deactivations")
        .and_return(double(body: "phone_number\r\n+14105556789\r\n+4105551234\n4105550000\n+24105559999\n\n"))

      # @lat: [[on-deactivated-phone-delete-user-job-design#Why only a real leading "+" is stripped]]
      expect(job.deactivated_phones).to eq(["4105556789", "4105551234", "4105550000"])
    end
  end
end
