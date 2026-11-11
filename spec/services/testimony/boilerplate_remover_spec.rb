# frozen_string_literal: true

require "rails_helper"

RSpec.describe Testimony::BoilerplateRemover do
  describe ".call" do
    it "strips the Baltimore City IT outside mail banner" do
      text = <<~TXT
        Dear Council Members,
        CAUTION:  This email originated from outside of Baltimore City IT Network Systems.
        Reminder:  DO NOT click links or open attachments unless you recognize the sender and know that the content is safe.
        Report any suspicious activities using the Report Phishing Email Button, or by emailing to Phishing@baltimorecity.gov
        I support Bill 169.
      TXT

      result = described_class.call(text)

      expect(result.text).to include("Dear Council Members,")
      expect(result.text).to include("I support Bill 169.")
      expect(result.text).not_to include("CAUTION:")
      expect(result.occurrences).to eq(1)
      expect(result.characters_removed).to be > 0
    end

    it "strips the City Council President Zeke Cohen office footer block" do
      text = <<~TXT
        From: test@example.com
        Office of the Baltimore City Council President Zeke Cohen 
        Baltimore City Council  
        100 Holliday Street, Room 400 
        Baltimore, MD 21202 
        Office: (410) 396-4804 
        Request the Council President for a meeting or event here 
        I support the Harford Road Overlay.
      TXT

      result = described_class.call(text)

      expect(result.text).to include("From: test@example.com")
      expect(result.text).to include("I support the Harford Road Overlay.")
      expect(result.text).not_to include("Office of the Baltimore City Council President Zeke Cohen")
      expect(result.text).not_to include("100 Holliday Street")
      expect(result.text).not_to include("(410) 396-4804")
      expect(result.text).not_to include("Request the Council President for a meeting or event here")
      expect(result.occurrences).to be >= 1
    end

    it "strips arbitrary Council Member office footers (e.g. Odette Ramos, Mark Conway, Ryan Dorsey)" do
      text = <<~TXT
        Dear Committee,
        Office of Councilwoman Odette Ramos
        Baltimore City Council, District 14
        100 Holliday Street, Room 500
        Baltimore, MD 21202
        Office: (410) 396-4814
        I am writing in support of the Harford Road Overlay.
      TXT

      result = described_class.call(text)

      expect(result.text).to include("Dear Committee,")
      expect(result.text).to include("I am writing in support of the Harford Road Overlay.")
      expect(result.text).not_to include("Office of Councilwoman Odette Ramos")
      expect(result.text).not_to include("100 Holliday Street")
      expect(result.text).not_to include("(410) 396-4814")
    end

    it "strips mobile device and email client footers" do
      text = "Dear Council,\nI support this bill.\n\nSent from my iPhone\n"

      result = described_class.call(text)

      expect(result.text).to include("Dear Council,")
      expect(result.text).to include("I support this bill.")
      expect(result.text).not_to include("Sent from my iPhone")
    end

    it "strips legal and confidentiality notice boilerplate" do
      text = <<~TXT
        Dear Council,
        We support the ordinance.
        CONFIDENTIALITY NOTICE:
        This message is intended only for the use of the individual to whom it is addressed.
        Please delete if received in error.
      TXT

      result = described_class.call(text)

      expect(result.text).to include("Dear Council,")
      expect(result.text).to include("We support the ordinance.")
      expect(result.text).not_to include("CONFIDENTIALITY NOTICE:")
      expect(result.text).not_to include("Please delete if received in error.")
    end

    it "stops a disclaimer block before the next letter's From: header when no blank line separates them" do
      text = <<~TXT
        From: first@example.com
        Dear Council,
        We support the ordinance.
        DISCLAIMER:
        These views are my own and not my employer's.
        From: second@example.com
        Sent: Friday, October 16, 2026 10:00 AM
        Subject: Support
        Dear Council,
        I also support this bill.
      TXT

      result = described_class.call(text)

      expect(result.text).not_to include("DISCLAIMER:")
      expect(result.text).not_to include("These views are my own")
      expect(result.text).to include("From: second@example.com")
      expect(result.text).to include("I also support this bill.")
    end

    it "preserves a formal constituent inside address to Baltimore City Council at 100 N. Holliday Street" do
      text = <<~TXT
        Baltimore City Council
        Land Use and Transportation Committee
        100 N. Holliday Street
        Baltimore, MD 21202

        Dear Council Members,
        On behalf of our neighborhood association, we urge a favorable report.
      TXT

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.occurrences).to eq(0)
    end

    it "strips short council office footers that omit 100 Holliday Street but carry a City Hall phone number" do
      text = <<~TXT
        Dear Committee,
        I support this bill.
        Office of Councilman Mark Conway
        4th District, Baltimore City Council
        Office: (410) 396-4807
      TXT

      result = described_class.call(text)

      expect(result.text).to include("I support this bill.")
      expect(result.text).not_to include("Office of Councilman Mark Conway")
      expect(result.text).not_to include("(410) 396-4807")
    end

    it "strips forward wrappers between letters without attaching them to the preceding letter" do
      text = <<~TXT
        From: Alice <alice@example.com>
        Subject: Support

        Dear Council,
        I strongly support the Harford Road Overlay.

        From:
        Cohen, Zeke (City Council)
        Sent:
        Thursday, October 15, 2026 8:57 AM
        To:
        Testimony
        Subject:
        Fw: Harford Road Overlay

        Office of the Baltimore City Council President Zeke Cohen
        Baltimore City Council
        100 Holliday Street, Room 400
        Baltimore, MD 21202
        Office: (410) 396-4804
        Request the Council President for a meeting or event here

        From: Bob <bob@example.com>
        Subject: Harford Road Overlay

        Dear Council,
        Please pass this bill for our corridor.
      TXT

      result = described_class.call(text)
      entries = Testimony::LetterSplitter.call(result.text)

      expect(entries.length).to eq(2)
      expect(entries.first.text).to include("From: Alice <alice@example.com>")
      expect(entries.first.text).not_to include("Cohen, Zeke")
      expect(entries.first.text).not_to include("Fw: Harford Road Overlay")
      expect(entries.last.text).to start_with("From: Bob <bob@example.com>")
      expect(result.characters_removed).to eq(text.length - result.text.length)
    end

    it "strips forward wrappers carrying internal staff routing notes like 'Good morning, please add to the bill file.'" do
      wrapper = <<~TXT
        From: Staffer <staffer@baltimorecity.gov>
        Sent: Friday, October 16, 2026 10:00 AM
        To: Testimony
        Subject: Fw: Bill 25-0169 Testimony

        Good morning, please add to the bill file.

      TXT
      constituent = <<~TXT
        From: Jane Resident <jane@example.com>
        Sent: Thursday, October 15, 2026 4:15 PM
        To: Staffer <staffer@baltimorecity.gov>
        Subject: Bill 25-0169 Testimony

        Dear Council,
        I strongly support this bill.
      TXT

      result = described_class.call("#{wrapper}#{constituent}")

      expect(result.text).to eq(constituent)
      expect(result.occurrences).to eq(1)
    end

    it "preserves third-person organization testimony and constituent narrative testimony mentioning 'for the hearing record' or 'please see below'" do
      org_letter = <<~TXT
        From: Director <director@housingcoalition.org>
        Sent: Friday, October 16, 2026 9:00 AM
        To: Testimony
        Subject: Bill 25-0064 Testimony

        The Baltimore Housing Coalition supports Bill 25-0064 and urges a favorable report. Please include our written testimony for the hearing record.

      TXT
      constituent_letter = <<~TXT
        From: Neighbor <neighbor@example.com>
        Sent: Friday, October 16, 2026 9:30 AM
        To: Testimony
        Subject: Bill 25-0064

        This zoning change will worsen traffic on Harford Road and hurt our neighborhood schools. Please see below my comments for the hearing record.
      TXT

      combined = "#{org_letter}#{constituent_letter}"
      result = described_class.call(combined)

      expect(result.text).to eq(combined)
      expect(result.occurrences).to eq(0)
      expect(described_class.internal_routing_note?(org_letter)).to be(false)
      expect(described_class.internal_routing_note?(constituent_letter)).to be(false)
    end
  end
end
