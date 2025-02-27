require "rails_helper"

RSpec.describe OnDeactivatedPhoneDeleteUserJob, type: :job do
  include_context "Setup"

  describe "the deactivation job is run" do
    context "a list of phone  numbers has been received" do
      it "destroys the users with inactive phone numbers" do
        _sway_locale, user = setup

        job = OnDeactivatedPhoneDeleteUserJob.new
        allow(job).to receive(:deactivated_phones).and_return([user.phone])
        allow(job).to receive(:perform).and_call_original
        job.perform

        expect(User.find_by(id: user.id)).to be_nil
      end

      it "does not destroy a user when their phone is not in the list" do
        _sway_locale, user = setup

        job = OnDeactivatedPhoneDeleteUserJob.new
        allow(job).to receive(:deactivated_phones).and_return(["1237779999"])
        allow(job).to receive(:perform).and_call_original
        job.perform

        expect(User.find_by(id: user.id)).to_not be_nil
      end
    end
  end
end
