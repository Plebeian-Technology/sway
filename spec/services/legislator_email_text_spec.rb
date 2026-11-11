# frozen_string_literal: true

require "rails_helper"

# LegislatorEmailText is the one place the email your legislator message is
# written. The mailer renders it, and BillsController#show reuses it as
# the modal preview.
RSpec.describe LegislatorEmailText do
  let(:user) do
    create(
      :user,
      full_name: "Taylor Voter",
      email: "voter@example.com",
      is_email_verified: true
    )
  end
  let(:district) { create(:district) }
  let(:legislator) do
    create(
      :legislator,
      district: district,
      email: "rep@example.gov",
      first_name: "Alex",
      last_name: "Jones",
      title: "Rep"
    ).tap { |l| create(:legislator_term, legislator: l, district: district, title: "Rep") }
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
  # The preview path constructs an UNSAVED row — pin that it works.
  let(:unsaved_row) do
    UserLegislatorEmail.new(user_legislator: user_legislator, bill: bill)
  end

  it "renders Support subject + support body from a FOR vote" do
    create(:user_vote, user: user, bill: bill, support: "FOR")
    text = described_class.new(unsaved_row)

    expect(text.subject).to eq("Support Bill HB-123")
    expect(text.body).to start_with("Please support bill HB-123")
    expect(text.intro).to include("Hello Rep Jones, my name is Taylor Voter")
    expect(text.conclusion).to eq("Thank you, Taylor Voter.")
  end

  it "renders Oppose subject + oppose body from an AGAINST vote" do
    create(:user_vote, user: user, bill: bill, support: "AGAINST")
    text = described_class.new(unsaved_row)

    expect(text.subject).to eq("Oppose Bill HB-123")
    expect(text.body).to start_with("Please oppose bill HB-123")
  end

  it "renders the ask-their-position body when the user has not voted" do
    text = described_class.new(unsaved_row)

    expect(text.subject).to eq("Bill HB-123")
    expect(text.body).to start_with("I am writing to you today because I would like to know your position")
  end

  it "substitutes a {YOUR NAME} placeholder in the preview when full_name is blank" do
    user.update!(full_name: nil)
    text = described_class.new(unsaved_row)

    expect(text.intro).to include("my name is {YOUR NAME}")
    expect(text.conclusion).to eq("Thank you, {YOUR NAME}.")
  end

  it "exposes the preview prop shape" do
    expect(described_class.new(unsaved_row).as_props.keys)
      .to match_array(%i[subject intro body conclusion bill_link])
  end

  it "is byte-identical with what the mailer renders (single source of truth)" do
    create(:user_vote, user: user, bill: bill, support: "FOR")
    persisted = UserLegislatorEmail.create!(user_legislator: user_legislator, bill: bill)
    text = described_class.new(persisted)
    mail = UserLegislatorEmailMailer.send_email_to_legislator(persisted)

    expect(mail.subject).to eq(text.subject)
    text_part = mail.text_part&.body&.decoded.to_s
    expect(text_part).to include(text.intro)
    expect(text_part).to include(text.body)
    expect(text_part).to include(text.conclusion)
  end

  context "when bill has no source link (nil)" do
    let(:unlinked_bill) do
      create(
        :bill,
        external_id: "HB-456",
        link: nil,
        legislator: legislator,
        sway_locale: legislator.sway_locale
      )
    end
    let(:unlinked_row) do
      UserLegislatorEmail.new(user_legislator: user_legislator, bill: unlinked_bill)
    end

    # @lat: [[outbound-email#Outbound email#The preview is built from the object the mailer renders]]
    it "suppresses the link clause from body and ends with a period" do
      text = described_class.new(unlinked_row)
      expect(text.bill_link).to be_nil
      expect(text.body).not_to include("which can be found here")
      expect(text.body).to end_with(".")
    end

    it "exposes nil bill_link in as_props" do
      expect(described_class.new(unlinked_row).as_props[:bill_link]).to be_nil
    end
  end

  context "when bill has a generic search URL" do
    let(:generic_bill) do
      create(
        :bill,
        external_id: "HB-789",
        link: "https://baltimore.legistar.com/LegislationSearch.aspx",
        legislator: legislator,
        sway_locale: legislator.sway_locale
      )
    end
    let(:generic_row) do
      UserLegislatorEmail.new(user_legislator: user_legislator, bill: generic_bill)
    end

    # @lat: [[outbound-email#Outbound email#The preview is built from the object the mailer renders]]
    it "treats generic search URLs as absent source links" do
      text = described_class.new(generic_row)
      expect(text.bill_link).to be_nil
      expect(text.body).not_to include("which can be found here")
      expect(text.body).to end_with(".")
    end
  end

  describe "generic portal URL filtering decoupling" do
    it "returns nil when the bill link matches a configured generic portal URL" do
      mock_locale = instance_double(SwayLocale, generic_portal_urls: ["https://custom.portal.gov", "https://custom.portal.gov/search"])
      allow(unsaved_row).to receive(:sway_locale).and_return(mock_locale)
      bill.update_columns(link: "https://custom.portal.gov/search")
      text = described_class.new(unsaved_row)

      expect(text.bill_link).to be_nil
      expect(text.body).to end_with(".")
    end

    it "returns the link when the bill link does not match configured generic portal URLs" do
      mock_locale = instance_double(SwayLocale, generic_portal_urls: ["https://custom.portal.gov", "https://custom.portal.gov/search"])
      allow(unsaved_row).to receive(:sway_locale).and_return(mock_locale)
      bill.update_columns(link: "https://custom.portal.gov/bills/HB-123")
      text = described_class.new(unsaved_row)

      expect(text.bill_link).to eq("https://custom.portal.gov/bills/HB-123")
      expect(text.body).to include("which can be found here - ")
    end

    it "is driven dynamically by generic_portal_urls and does not filter former hardcoded domains when omitted from config" do
      mock_locale = instance_double(SwayLocale, generic_portal_urls: [])
      allow(unsaved_row).to receive(:sway_locale).and_return(mock_locale)
      bill.update_columns(link: "https://baltimore.legistar.com")
      text = described_class.new(unsaved_row)

      expect(text.bill_link).to eq("https://baltimore.legistar.com")
    end
  end
end
