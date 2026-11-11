# frozen_string_literal: true

require "rails_helper"

RSpec.describe Testimony::StanceRules do
  describe ".classify" do
    it "returns nil for blank or purely informational text" do
      expect(described_class.classify(nil)).to be_nil
      expect(described_class.classify("")).to be_nil
      expect(described_class.classify("Here is background data and fiscal information regarding this matter.")).to be_nil
    end

    it "classifies 'Please vote NO or at least abstain from voting.' as oppose" do
      letter = <<~TXT
        Dear City Council Members,

        This zoning change will harm our neighborhood infrastructure.
        Please vote NO or at least abstain from voting.
      TXT

      expect(described_class.classify(letter)).to eq("oppose")
    end

    it "classifies explicit oppose directives and headers as oppose" do
      expect(described_class.classify("I strongly oppose this legislation and urge an unfavorable report.")).to eq("oppose")
      expect(described_class.classify("Please do not pass Bill 25-0064.")).to eq("oppose")
      expect(described_class.classify("We are writing in opposition to Council Bill 26-0093.")).to eq("oppose")
      expect(described_class.classify("Subject: OPPOSE Bill 25-0064\n\nPlease consider the traffic impact.")).to eq("oppose")
      expect(described_class.classify("Position: Unfavorable\n\nThe committee should table this measure.")).to eq("oppose")
    end

    it "classifies explicit support directives and headers as support" do
      expect(described_class.classify("I strongly support this bill and urge a favorable report.")).to eq("support")
      expect(described_class.classify("Please vote YES on Council Bill 25-0064.")).to eq("support")
      expect(described_class.classify("I am writing today to urge you to support Bill 25-0064. Please pass this important bill.")).to eq("support")
      expect(described_class.classify("Position: Favorable with Amendments\n\nWe recommend advancing this measure.")).to eq("support")
      expect(described_class.classify("Subject: Support for Bill 25-0064\n\nThank you for your leadership.")).to eq("support")
    end

    it "does not misread negated support ('do not support', 'cannot support') as support" do
      expect(described_class.classify("I do not support this bill in its current form.")).to eq("oppose")
      expect(described_class.classify("We cannot support Council Bill 25-0064.")).to eq("oppose")
    end

    it "does not misread negated oppose ('do not oppose') as oppose" do
      expect(described_class.classify("We do not oppose the committee's inquiry into this topic.")).to be_nil
    end

    it "returns nil when a letter contains conflicting support and oppose directives" do
      mixed = "Some residents urge a favorable report, while others urge an unfavorable report."
      expect(described_class.classify(mixed)).to be_nil
    end

    it "does not misclassify bill titles containing 'Peer Support Services' or 'Protection Against Discrimination' on Subject/Re/Bill headers" do
      peer_support_opposing = "Subject: Bill 25-0200 - Peer Support Services\n\nI strongly oppose this bill and urge an unfavorable report."
      peer_support_neutral = "Re: Bill 25-0200 - Peer Support Services\n\nHere is our agency fiscal note on the program."
      discrimination_supporting = "Bill: CB 25-0100 - Protection Against Discrimination\n\nI strongly support this bill and urge a favorable report."
      discrimination_neutral = "Subject: Protection Against Discrimination\n\nAttached is background data for the hearing."

      expect(described_class.classify(peer_support_opposing)).to eq("oppose")
      expect(described_class.classify(peer_support_neutral)).to be_nil
      expect(described_class.classify(discrimination_supporting)).to eq("support")
      expect(described_class.classify(discrimination_neutral)).to be_nil
    end

    it "returns nil when header stance and body stance conflict" do
      conflict_support_header = "Position: Support\n\nI strongly oppose this legislation and urge an unfavorable report."
      conflict_oppose_header = "Stance: Oppose\n\nI strongly support this bill and urge a favorable report."

      expect(described_class.classify(conflict_support_header)).to be_nil
      expect(described_class.classify(conflict_oppose_header)).to be_nil
    end

    it "does not match prepositional 'for' in neutral/informational Position headers, returns nil on mixed single-line headers, and matches chamber prefixes in Subject headers" do
      expect(described_class.classify("Position: Informational testimony for the committee\n\nHere is our analysis.")).to be_nil
      expect(described_class.classify("Position: Neutral — submitted for the record\n\nAttached are the figures.")).to be_nil
      expect(described_class.classify("Position: For\n\nThank you for considering this.")).to eq("support")
      expect(described_class.classify("Position: [ ] Favorable [ ] Unfavorable\n\nHere are the agency details.")).to be_nil
      expect(described_class.classify("Position: Support / Oppose\n\nPlease review our comments.")).to be_nil
      expect(described_class.classify("Subject: Oppose Council Bill 25-0064\n\nPlease consider the traffic impact.")).to eq("oppose")
      expect(described_class.classify("Subject: Support for Council Bill 25-0064\n\nThank you for your leadership.")).to eq("support")
    end
  end
end
