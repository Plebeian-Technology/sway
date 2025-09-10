require "rails_helper"

RSpec.describe OnUserEmailSavedSendEmailToLegislatorJob, type: :job do
    include_context "Setup"

    describe "a user sends emails to their legislators" do
        context "after voting on a bill and creating a user_vote" do
            it "sends an email to each of the user's legislators" do
                sway_locale, user = setup

                legislator = create(:legislator)
                bill = create(:bill, legislator:, sway_locale:)
                create(:user_vote, user:, bill:)
                user_legislator = create(:user_legislator, user:, legislator:)
                user_legislator_email = UserLegislatorEmail.new(user_legislator:, bill:)
                allow(user_legislator_email).to receive(:sendable?).and_return(true)

                sent_mail_double = double("DoubleSentMail", error_status: nil)
                mailer_double = double("DoubleMailer", deliver_now!: sent_mail_double)
                mailer = class_double("UserLegislatorEmailMailer").as_stubbed_const
                expect(mailer).to receive(:send_email_to_legislator).with(user_legislator_email).and_return(mailer_double)

                OnUserEmailSavedSendEmailToLegislatorJob.new.perform(user_legislator_email)

                expect(user_legislator_email.status).to eql("sent")
            end
        end
    end
end
