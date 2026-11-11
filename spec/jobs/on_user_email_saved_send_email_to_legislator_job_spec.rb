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
        expect(mailer).to receive(:send_email_to_legislator).with(
          user_legislator_email
        ).and_return(mailer_double)

        OnUserEmailSavedSendEmailToLegislatorJob.new.perform(
          user_legislator_email
        )

        expect(user_legislator_email.status).to eql("sent")
      end
    end

    # @lat: [[on-user-email-saved-send-email-job-design#Why only two exception classes are retried]]
    # @lat: [[steep-typed-spec-helpers#Why spec/jobs/on_user_email_saved_send_email_to_legislator_job_spec.rb repeats its setup instead of a def helper]]
    context "when delivery raises" do
      it "re-arms to failed and retries on a PRE-SEND transient (Net::OpenTimeout)" do
        sway_locale, user = setup
        legislator = create(:legislator)
        bill = create(:bill, legislator:, sway_locale:)
        user_legislator = create(:user_legislator, user:, legislator:)
        ule = UserLegislatorEmail.create!(user_legislator:, bill:)
        allow(ule).to receive(:sendable?).and_return(true)

        mailer_double = double("DoubleMailer")
        # Net::OpenTimeout means the connection never opened, so nothing was
        # sent — safe to retry automatically.
        allow(mailer_double).to receive(:deliver_now!).and_raise(Net::OpenTimeout)
        mailer = class_double("UserLegislatorEmailMailer").as_stubbed_const
        allow(mailer).to receive(:send_email_to_legislator).and_return(mailer_double)

        # retry_on swallows the passing error and queues the job again. Use
        # perform_now, not .new.perform, so that retry_on's rescue is in play.
        expect {
          described_class.perform_now(ule)
        }.to have_enqueued_job(described_class)

        expect(ule.reload.status).to eql("failed")
      end

      # @lat: [[on-user-email-saved-send-email-job-design#Why only two exception classes are retried]]
      it "does NOT auto-retry an ambiguous post-send timeout (avoids duplicate email)" do
        sway_locale, user = setup
        legislator = create(:legislator)
        bill = create(:bill, legislator:, sway_locale:)
        user_legislator = create(:user_legislator, user:, legislator:)
        ule = UserLegislatorEmail.create!(user_legislator:, bill:)
        allow(ule).to receive(:sendable?).and_return(true)

        mailer_double = double("DoubleMailer")
        allow(mailer_double).to receive(:deliver_now!).and_raise(Net::ReadTimeout)
        mailer = class_double("UserLegislatorEmailMailer").as_stubbed_const
        allow(mailer).to receive(:send_email_to_legislator).and_return(mailer_double)

        expect {
          begin
            described_class.perform_now(ule)
          rescue Net::ReadTimeout
            nil # expected: it is not retried, so it comes back out here
          end
        }.not_to have_enqueued_job(described_class)

        expect(ule.reload.status).to eql("failed")
      end

      # Writing the `sending` status uses update!, so a write that fails raises
      # and leaves the row at `failed`, instead of going ahead and delivering
      # against a row that was never marked `sending`. Before the fix, the
      # non-bang `update` just returned false and the send happened anyway.
      it "guards the send: a failed sending-status write raises instead of emailing" do
        sway_locale, user = setup
        legislator = create(:legislator)
        bill = create(:bill, legislator:, sway_locale:)
        user_legislator = create(:user_legislator, user:, legislator:)
        ule = UserLegislatorEmail.create!(user_legislator:, bill:)
        allow(ule).to receive(:sendable?).and_return(true)

        # Make saving the `sending` status fail: save! raises, which is what
        # update! calls, and save returns false, which is both the old update
        # path and what the rescue uses to re-arm the row.
        allow(ule).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(ule))
        allow(ule).to receive(:save).and_return(false)

        expect(ule).not_to receive(:send_email)

        expect {
          described_class.new.perform(ule)
        }.to raise_error(ActiveRecord::RecordInvalid)
      end

      it "re-arms to failed and re-raises a non-transient error without retrying" do
        sway_locale, user = setup
        legislator = create(:legislator)
        bill = create(:bill, legislator:, sway_locale:)
        user_legislator = create(:user_legislator, user:, legislator:)
        ule = UserLegislatorEmail.create!(user_legislator:, bill:)
        allow(ule).to receive(:sendable?).and_return(true)

        mailer_double = double("DoubleMailer")
        allow(mailer_double).to receive(:deliver_now!).and_raise(RuntimeError.new("boom"))
        mailer = class_double("UserLegislatorEmailMailer").as_stubbed_const
        allow(mailer).to receive(:send_email_to_legislator).and_return(mailer_double)

        expect {
          described_class.perform_now(ule)
        }.to raise_error(RuntimeError, "boom")

        expect(ule.reload.status).to eql("failed")
      end

      it "skips sending when another worker has already claimed the row as sending in the DB" do
        sway_locale, user = setup
        legislator = create(:legislator)
        bill = create(:bill, legislator:, sway_locale:)
        user_legislator = create(:user_legislator, user:, legislator:)
        ule = UserLegislatorEmail.create!(user_legislator:, bill:)
        allow(ule).to receive(:sendable?).and_return(true)

        UserLegislatorEmail.where(id: ule.id).update_all(status: UserLegislatorEmail.statuses["sending"])

        expect(ule).not_to receive(:send_email)
        described_class.new.perform(ule)
      end
    end
  end
end
