# frozen_string_literal: true

require "rails_helper"

RSpec.describe InboundSmsForwardingService do
  include ActiveJob::TestHelper

  # @lat: [[inbound-sms#Inbound SMS#Suppression is only proved by running the job]]
  def forward_sms(from: "+14105551234", body: "Hello there")
    perform_enqueued_jobs { described_class.new(from: from, body: body).call }
  end

  def last_forwarded_mail
    ActionMailer::Base.deliveries.last
  end

  def last_forwarded_mail_text
    mail = last_forwarded_mail
    (mail.text_part || mail).body.to_s
  end

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  before { ActionMailer::Base.deliveries.clear }

  describe "what reaches the inbox" do
    it "emails an ordinary message to the configured address" do
      expect { forward_sms(body: "Is Sway available in my city?") }
        .to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(last_forwarded_mail.to).to eq([Sway::Settings.ops.inbound_sms_forward_to])
      expect(last_forwarded_mail_text).to include("Is Sway available in my city?")
    end

    it "puts the sender's number in the body so a reply can be addressed" do
      forward_sms(from: "+14105551234", body: "Question")

      expect(last_forwarded_mail_text).to include("+14105551234")
    end
  end

  # @lat: [[inbound-sms#Inbound SMS#Keyword messages are not forwarded]]
  describe "keyword messages are never forwarded" do
    %w[STOP STOPALL UNSUBSCRIBE CANCEL END QUIT OPTOUT REVOKE START YES UNSTOP SUBSCRIBE HELP INFO].each do |keyword|
      it "ignores #{keyword}" do
        expect { forward_sms(body: keyword) }
          .not_to change { ActionMailer::Base.deliveries.size }
      end
    end

    it "ignores a keyword regardless of case or surrounding whitespace" do
      expect { forward_sms(body: "  stop  ") }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "still forwards a message that merely contains a keyword as a word" do
      expect { forward_sms(body: "Please stop sending me bills about parking") }
        .to change { ActionMailer::Base.deliveries.size }.by(1)
    end
  end

  describe "sender identification" do
    it "marks a message from a known user as known" do
      create(:user, phone: "4105551234")

      forward_sms(from: "+14105551234", body: "Hello")

      expect(last_forwarded_mail.subject).to include("known user")
    end

    it "marks a message from a stranger as unknown" do
      forward_sms(from: "+14105559999", body: "Hello")

      expect(last_forwarded_mail.subject).to include("unknown")
    end
  end

  # @lat: [[inbound-sms#Inbound SMS#The spam rule is a link from a stranger]]
  describe "spam" do
    it "drops a link from a sender who is not a Sway user" do
      expect { forward_sms(from: "+14105559999", body: "Your parcel: https://example.com/track") }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "forwards a link from a known user, who is entitled to send one" do
      create(:user, phone: "4105551234")

      expect { forward_sms(from: "+14105551234", body: "Look at https://example.com") }
        .to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    it "forwards a stranger's message that carries no link" do
      expect { forward_sms(from: "+14105559999", body: "How do I sign up?") }
        .to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    it "treats a bare domain as a link, since spam rarely writes the scheme" do
      expect { forward_sms(from: "+14105559999", body: "claim now at example.com/x") }
        .not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  describe "empty input" do
    it "sends nothing when the body is blank" do
      expect { forward_sms(body: "") }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "sends nothing when the sender is blank" do
      expect { forward_sms(from: "", body: "Hello") }
        .not_to change { ActionMailer::Base.deliveries.size }
    end
  end
end
