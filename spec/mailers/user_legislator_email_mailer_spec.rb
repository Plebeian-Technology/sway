require "rails_helper"

RSpec.describe UserLegislatorEmailMailer, type: :mailer do
  describe "#send_email_to_legislator" do
    let(:user) do
      create(
        :user,
        full_name: "Taylor Voter",
        email: "voter@example.com",
        is_email_verified: true
      )
    end
    let(:legislator) do
      create(
        :legislator,
        email: "rep@example.gov",
        first_name: "Alex",
        last_name: "Jones",
        title: "Rep"
      )
    end
    let(:bill) do
      create(
        :bill,
        external_id: "HB-123",
        legislator: legislator,
        sway_locale: legislator.sway_locale
      )
    end
    let(:user_legislator) do
      create(:user_legislator, user: user, legislator: legislator)
    end
    let(:user_legislator_email) do
      UserLegislatorEmail.create!(user_legislator: user_legislator, bill: bill)
    end
    let(:mail) do
      described_class.send_email_to_legislator(user_legislator_email)
    end

    # The default from-address on the class must be a real Sway address, not the
    # example.com placeholder. It is what bounced mail and any action that does
    # not set its own from: will use.
    it "uses a real Sway default from-address, not an example.com placeholder" do
      expect(UserLegislatorEmailMailer.default[:from]).to eq("outreach@sway.vote")
      expect(UserLegislatorEmailMailer.default[:from].to_s).not_to include("example.com")
    end

    it "renders message headers" do
      expect(mail.from).to eq(["outreach@sway.vote"])
      expect(mail.to).to eq(["rep@sway.vote"])
      expect(mail.cc).to eq([user.email])
      expect(mail.reply_to).to eq([user.email])
      expect(mail.subject).to eq("Bill #{bill.external_id}")
    end

    it "renders message body" do
      expect(mail.body.encoded).to include(user.full_name)
      expect(mail.body.encoded).to include(bill.external_id)
      expect(mail.body.encoded).to include(bill.link)
    end

    context "when the user voted for the bill" do
      before { create(:user_vote, user: user, bill: bill, support: "for") }

      it "uses a support subject line" do
        expect(mail.subject).to eq("Support Bill #{bill.external_id}")
      end
    end

    context "when the user voted against the bill" do
      before { create(:user_vote, user: user, bill: bill, support: "against") }

      it "uses an oppose subject line" do
        expect(mail.subject).to eq("Oppose Bill #{bill.external_id}")
      end
    end

    context "when the bill has no source link (nil)" do
      let(:bill) do
        create(
          :bill,
          external_id: "HB-123",
          link: nil,
          legislator: legislator,
          sway_locale: legislator.sway_locale
        )
      end

      # @lat: [[outbound-email#Outbound email#The preview is built from the object the mailer renders]]
      it "renders both html and text parts without raising and without dangling link clauses" do
        expect { mail.body.encoded }.not_to raise_error
        html_part = mail.html_part&.body&.decoded.to_s
        text_part = mail.text_part&.body&.decoded.to_s

        expect(html_part).not_to include("which can be found here")
        expect(text_part).not_to include("which can be found here")
        expect(html_part).to include(bill.external_id)
        expect(text_part).to include(bill.external_id)
      end
    end
  end
end
