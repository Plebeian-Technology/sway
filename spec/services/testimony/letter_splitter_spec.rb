# frozen_string_literal: true

require "rails_helper"
require "support/testimony_fixtures"

# Turns the cleaned bundle (one long string) into a
# list of letters. Everything downstream reads this list, not the bundle
# string, so a defect here understates or inflates every later count.
RSpec.describe Testimony::LetterSplitter do
  describe ".call" do
    it "splits the campaign fixture into one entry per letter marker" do
      # Measured with `grep -c "^From:" spec/fixtures/testimony/campaign_bundle.txt`.
      # Hard-coded rather than re-derived so a fixture edit that silently drops
      # a marker is caught here instead of passing for the wrong reason.
      entries = described_class.call(TestimonyFixtures.campaign_bundle)

      expect(entries.length).to eq(42)
    end

    it "gives each entry its own zero-based position, in bundle order" do
      entries = described_class.call(TestimonyFixtures.campaign_bundle)

      expect(entries.map(&:position)).to eq((0...entries.length).to_a)
    end

    it "gives each entry the character offset where its own text really begins" do
      bundle = TestimonyFixtures.campaign_bundle
      entries = described_class.call(bundle)

      entries.each do |entry|
        expect(bundle[entry.character_offset, 5]).to eq(entry.text[0, 5])
      end
    end

    it "returns an empty list for blank text and does not raise" do
      expect(described_class.call("")).to eq([])
      expect(described_class.call("   \n  \t")).to eq([])
    end

    it "returns a single entry holding the whole text when there is no marker at all" do
      text = "Dear Council, I support this bill for my own reasons.\n"

      entries = described_class.call(text)

      expect(entries.length).to eq(1)
      expect(entries.first.position).to eq(0)
      expect(entries.first.character_offset).to eq(0)
      expect(entries.first.text).to eq(text)
    end

    it "keeps text before the first marker as its own preamble entry rather than dropping it" do
      text = "A clerk's cover note ahead of the first letter.\n\n" \
        "From: Jane Doe <jane@example.com>\nDear Council,\nI support this.\n"

      entries = described_class.call(text)

      expect(entries.length).to eq(2)
      expect(entries.first.character_offset).to eq(0)
      expect(entries.first.text).to include("A clerk's cover note")
      expect(entries.last.text).to start_with("From: Jane Doe")
    end

    it "treats two letters with identical text as two entries, distinguished by position" do
      one_letter = "From: Jane Doe <jane@example.com>\nDear Council,\nI support this.\n\n"
      text = one_letter * 2

      entries = described_class.call(text)

      expect(entries.length).to eq(2)
      expect(entries.map(&:text).uniq.length).to eq(1)
      expect(entries.map(&:position)).to eq([0, 1])
    end

    it "does not match the marker mid-line, so a quoted reply inside a letter body is not a new letter" do
      text = "From: Jane Doe <jane@example.com>\nDear Council,\n> From: someone else\nI support this.\n"

      entries = described_class.call(text)

      expect(entries.length).to eq(1)
    end

    # @lat: [[testimony-letters#The splitter is biased toward leaving letters joined]]
    describe "the under-splitting bias" do
      it "splits on a column-zero From: with no blank line above it — extraction loses blank lines, and the marker is what disqualifies a split" do
        text = "some body text\nFrom: jane <jane@example.com>\nmore text\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(2)
        expect(entries.last.text).to start_with("From: jane")
      end

      it "keeps a clerk's cover note as its own entry rather than merging the letter under it into the note" do
        text = "A clerk's cover note with no blank line before the header.\n" \
          "From: Jane Doe <jane@example.com>\nDear Council,\nI support this.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(2)
        expect(entries.last.text).to start_with("From: Jane Doe")
      end

      it "does not split a forwarded header whose horizontal rule sits directly above From: with no blank line between" do
        text = "Dear Council,\nI support this on my own behalf.\n\n" \
          "________________________________\n" \
          "From: Original Sender <orig@example.com>\nSent: Monday\nSubject: fwd\n\nOriginal body text.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(1)
      end

      it "does not split a forwarded header introduced by 'Begin forwarded message:' even with a blank line before From:" do
        text = "Dear Council,\nI support this on my own behalf.\n\n" \
          "Begin forwarded message:\n\n" \
          "From: Original Sender <orig@example.com>\nSubject: fwd\n\nOriginal body text.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(1)
      end

      it "does not split a forwarded header introduced by '-----Original Message-----' even with a blank line before From:" do
        text = "Dear Council,\nI support this on my own behalf.\n\n" \
          "-----Original Message-----\n\n" \
          "From: Original Sender <orig@example.com>\nSubject: fwd\n\nOriginal body text.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(1)
      end

      it "does not split a quoted reply introduced by 'On <date> ... wrote:' even with a blank line before From:" do
        text = "Dear Council,\nI support this on my own behalf.\n\n" \
          "On Mon, Jun 2, 2026 at 3:00 PM, John Doe <john@example.com> wrote:\n\n" \
          "From: Original Sender <orig@example.com>\nSubject: fwd\n\nOriginal body text.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(1)
      end

      it "splits an ordinary blank-line-separated divider, because a bare dash rule is not a forward marker" do
        text = "Thank you,\nJane Doe\n100 Example Street\nBaltimore, MD 21201\n\n" \
          "----------------------------------------\n\n" \
          "From: Second Sender <second@example.com>\nSent: Monday\n\nDear Council,\nI support this too.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(2)
        expect(entries.last.text).to start_with("From: Second Sender")
      end

      it "collapses an empty forward wrapper header into the constituent letter rather than creating an empty stub" do
        text = "From:\nCohen, Zeke (City Council)\n" \
          "Sent:\nThursday, October 15, 2026 8:57 AM\n" \
          "To:\nTestimony\n" \
          "Subject:\nFw: Harford Road Overlay\n\n" \
          "From: Constituent <user@example.com>\n" \
          "Sent: Wednesday, October 14, 2026 5:00 PM\n" \
          "To: Cohen, Zeke\n" \
          "Subject: Harford Road Overlay\n\n" \
          "Dear Council,\nI am writing to support the Harford Road Overlay bill.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(1)
        expect(entries.first.text).to start_with("From: Constituent")
      end

      it "collapses forward wrappers carrying different Council Member footers (e.g. Odette Ramos)" do
        text = "From:\nRamos, Odette (City Council)\n" \
          "Sent:\nThursday, October 15, 2026 9:12 AM\n" \
          "To:\nTestimony\n" \
          "Subject:\nFw: Support for Harford Road\n\n" \
          "Office of Councilwoman Odette Ramos\n" \
          "14th District\n" \
          "100 Holliday Street, Room 500\n" \
          "Baltimore, MD 21202\n" \
          "Office: (410) 396-4814\n\n" \
          "From: Resident <resident@example.com>\n" \
          "Sent: Wednesday, October 14, 2026 6:00 PM\n" \
          "To: Ramos, Odette\n" \
          "Subject: Support for Harford Road\n\n" \
          "Dear Councilwoman Ramos,\nI urge you to support the overlay.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(1)
        expect(entries.first.text).to start_with("From: Resident")
      end

      it "collapses forward wrappers with custom or unknown footers when Subject has Fw:" do
        text = "From: Staffer <staffer@baltimorecity.gov>\n" \
          "Sent: Friday, October 16, 2026 10:00 AM\n" \
          "To: Testimony\n" \
          "Subject: Fwd: Testimony submission\n\n" \
          "FYI - passing along another constituent submission.\n" \
          "Sent from my iPad\n\n" \
          "From: Citizen <citizen@example.com>\n" \
          "Sent: Friday, October 16, 2026 9:30 AM\n" \
          "To: Staffer\n" \
          "Subject: Testimony submission\n\n" \
          "Dear Committee,\nHere is my written testimony.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(1)
        expect(entries.first.text).to start_with("From: Citizen")
      end

      it "drops a mid-bundle forward wrapper without appending it to the preceding constituent letter" do
        text = "From: First Resident <first@example.com>\n" \
          "Subject: My testimony\n\n" \
          "Dear Council,\nI support this bill.\n\n" \
          "From: Staffer <staffer@baltimorecity.gov>\n" \
          "Sent: Friday, October 16, 2026 10:00 AM\n" \
          "To: Testimony\n" \
          "Subject: Fw: Second testimony\n\n" \
          "Jane Staffer | Chief of Staff | District 3\n" \
          "________________________________\n" \
          "From: Second Resident <second@example.com>\n" \
          "Sent: Friday, October 16, 2026 9:30 AM\n" \
          "Subject: Second testimony\n\n" \
          "Dear Council,\nI oppose this bill.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(2)
        expect(entries.first.text).to start_with("From: First Resident")
        expect(entries.first.text).not_to include("From: Staffer")
        expect(entries.first.text).not_to include("Jane Staffer")
        expect(entries.last.text).to start_with("From: Second Resident")
      end

      it "preserves a short constituent letter that carries Fw: in its Subject: line" do
        text = "From: Jane Resident <jane@example.com>\n" \
          "Subject: Fw: Harford Road Overlay\n\n" \
          "Dear Council,\nPlease pass the Harford Road Overlay! Our neighborhood needs this.\n\n" \
          "From: Bob Smith <bob@example.com>\n" \
          "Subject: Harford Road Overlay\n\n" \
          "Dear Council,\nI also support this bill.\n"

        entries = described_class.call(text)

        expect(entries.length).to eq(2)
        expect(entries.first.text).to start_with("From: Jane Resident")
        expect(entries.last.text).to start_with("From: Bob Smith")
      end
    end

    # @lat: [[testimony-letters#Attachment boundaries and the five-page constituent ceiling]]
    describe "attachment boundaries, memo headers, and the five-page constituent ceiling" do
      it "splits concatenated non-email attachments across form-feed + blank-line boundaries and folds a clerk print-header stub forward into the following From: letter" do
        att_one = "DEPARTMENT OF FINANCE\nPosition: Finance is reporting on this bill.\f\n"
        att_two = "DEPARTMENT OF TRANSPORTATION\nBILL SYNOPSIS\nTransportation report.\f\n"
        email_stub_and_letter = "1\nClerk Name (City Council)\n\nFrom: Jane Resident <jane@example.com>\nDear Council,\nI support this bill.\f\n"
        bundle = [att_one, att_two, email_stub_and_letter].join("\n\n")

        entries = described_class.call(bundle)

        expect(entries.length).to eq(3)
        expect(entries[0].text).to start_with("DEPARTMENT OF FINANCE")
        expect(entries[1].text).to start_with("DEPARTMENT OF TRANSPORTATION")
        expect(entries[1].text).not_to include("Clerk Name (City Council)")
        expect(entries[2].text).to start_with("1\nClerk Name (City Council)\n\nFrom: Jane Resident")
        expect(entries.map(&:text).join).to eq(bundle)
      end

      it "folds a leading clerk print-header stub at offset 0 into the following From: letter as a single entry" do
        bundle = "1\nClerk Name (City Council)\n\nFrom: Jane Resident <jane@example.com>\nDear Council,\nI support this bill.\f\n"

        entries = described_class.call(bundle)

        expect(entries.length).to eq(1)
        expect(entries.first.text).to eq(bundle)
      end

      it "does not split a MEMORANDUM header between To: and From: when no prior From: appeared on the page" do
        memo = <<~TXT
          MEMORANDUM
          To: Honorable Members of the Committee
          From: Office of the Independent Analyst
          Date: October 15, 2026

          This memorandum analyzes the fiscal impact of the bill.
        TXT

        entries = described_class.call(memo)

        expect(entries.length).to eq(1)
        expect(entries.first.text).to eq(memo)
      end

      it "sub-splits a multi-page non-From: packet exceeding five pages at page-top letter cues" do
        pages = [
          "Dear Chair and Members of the Committee,\nI am writing to support this legislation for our block.",
          "Second page of the first constituent's letter continuing the argument.",
          "Dear Council President and Members,\nAs a small business owner, I also urge a favorable report.",
          "Written Testimony in Support of the Bill\nSubmitted by Resident Three.",
          "Honorable Members of the Committee,\nPlease vote yes on this measure.",
          "Good afternoon Chair and Committee,\nMy name is Resident Five and I support this bill."
        ]
        bundle = pages.map { |p| "#{p}\f\n" }.join

        entries = described_class.call(bundle)

        expect(entries.length).to eq(5)
        expect(entries[0].text).to include("Second page of the first constituent's letter")
        expect(entries[1].text).to start_with("Dear Council President")
        expect(entries[2].text).to start_with("Written Testimony in Support")
        expect(entries[3].text).to start_with("Honorable Members")
        expect(entries[4].text).to start_with("Good afternoon")
        expect(entries.map(&:text).join).to eq(bundle)
      end

      it "caps a From:-headed letter after five effective pages when followed by an unheaded multi-page report exceeding five pages" do
        email_pages = [
          "From: Sender <sender@example.com>\nSubject: Testimony and study\n\nPlease see our comments."
        ] + (2..5).map { |n| "Page #{n} of constituent cover letter with full arguments." }
        extra_pages = (1..6).map { |n| "Corridor analysis part #{n} with detailed tables." }
        bundle = (email_pages + extra_pages).map { |p| "#{p}\f\n" }.join

        entries = described_class.call(bundle)

        expect(entries.length).to eq(2)
        expect(entries.first.text).to start_with("From: Sender")
        expect(Testimony::ExtractedText.effective_page_count(entries.first.text)).to eq(5)
        expect(entries.last.text).to start_with("Corridor analysis part 1")
        expect(Testimony::ExtractedText.over_constituent_page_limit?(entries.last.text)).to be true
        expect(entries.map(&:text).join).to eq(bundle)
      end

      it "splits a 1-page From: cover email mentioning 'attached' right before a >= 6-page report starting with 'Section 1' or an all-caps title heading" do
        email_page = "From: Sender <sender@example.com>\nSubject: Testimony and study\n\nPlease see our attached comments."
        extra_pages = [
          "HARFORD ROAD CORRIDOR TECHNICAL STUDY\nPrepared for the 2026 hearing."
        ] + (2..6).map { |n| "Part #{n} of attached technical corridor analysis with detailed tables." }
        bundle = ([email_page] + extra_pages).map { |p| "#{p}\f\n" }.join

        entries = described_class.call(bundle)

        expect(entries.length).to eq(2)
        expect(entries.first.text).to start_with("From: Sender")
        expect(Testimony::ExtractedText.effective_page_count(entries.first.text)).to eq(1)
        expect(entries.last.text).to start_with("HARFORD ROAD CORRIDOR TECHNICAL STUDY")
        expect(Testimony::ExtractedText.over_constituent_page_limit?(entries.last.text)).to be true
        expect(entries.map(&:text).join).to eq(bundle)
      end

      it "does not split a multi-page study on wrapped 'Honorable ... asked', 'To the Council's credit', or 'Appendix A\nMEMORANDUM'" do
        study_pages = [
          "CORRIDOR TRAFFIC STUDY\nPage 1 analysis of corridor volume.",
          "In the prior committee session,\nHonorable Conway asked whether the traffic counts included weekend buses.",
          "With respect\nTo the Council's credit, the earlier amendment addressed parking minimums",
          "Appendix A\nMEMORANDUM\nBackground traffic methodology for the 2008 survey.",
          "14\nExhibit B\nTo: Project File\nFrom: Consultant\nSummary of intersections.",
          "Page 6 conclusion of the corridor traffic study."
        ]
        bundle = study_pages.map { |p| "#{p}\f\n" }.join

        entries = described_class.call(bundle)

        expect(entries.length).to eq(1)
        expect(Testimony::ExtractedText.over_constituent_page_limit?(entries.first.text)).to be true
      end

      it "keeps a From: cover email and an attached <= 5-page formal letter together so sender_address is not severed" do
        email_page = "From: Sender <sender@example.com>\nSubject: My formal letter\n\nPlease see my testimony."
        letter_pages = [
          "Dear Council President and Members,\nPage 1 of my formal letter.",
          "Page 2 of my formal letter.",
          "Page 3 of my formal letter.",
          "Page 4 of my formal letter.",
          "Page 5 of my formal letter."
        ]
        bundle = ([email_page] + letter_pages).map { |p| "#{p}\f\n" }.join

        entries = described_class.call(bundle)

        expect(entries.length).to eq(1)
        expect(entries.first.text).to start_with("From: Sender")
      end

      it "does not split a From:-headed letter when the remaining unheaded tail is five pages or fewer, avoiding an unheaded constituent-sized fragment" do
        email_page = "From: Sender <sender@example.com>\nSubject: Six-page letter\n\nPage 1 of my testimony."
        continuation_pages = (2..6).map { |n| "Page #{n} of my testimony continuing my personal remarks." }
        bundle = ([email_page] + continuation_pages).map { |p| "#{p}\f\n" }.join

        entries = described_class.call(bundle)

        expect(entries.length).to eq(1)
        expect(Testimony::ExtractedText.over_constituent_page_limit?(entries.first.text)).to be true
      end

      it "does not split on lowercase mid-sentence page wraps or spillover closing blocks" do
        pages = [
          "Dear Council President and Members,\nI am writing to explain how the proposed zoning change affects the alley next",
          "to the house where my family has lived for thirty years and why we care.",
          "Furthermore, the previous hearing record shows that residents raised concerns about",
          "testimony on the traffic study that was never answered by the developer.",
          "We also spoke with neighbors and",
          "members of the community who walk along this corridor every single day.",
          "Thank you for this opportunity to provide testimony on this important matter.\nSincerely,\nJane Doe"
        ]
        bundle = pages.map { |p| "#{p}\f\n" }.join

        entries = described_class.call(bundle)

        expect(entries.length).to eq(1)
        expect(entries.first.text).to eq(bundle)
      end

      it "splits a short constituent note without sentence-ending punctuation instead of skipping it as a print-header stub" do
        short_note = "Dear Council,\nPlease vote yes\nJane Doe"
        other_pages = (1..5).map { |n| "Dear Council,\nPage #{n} of another constituent letter with full sentences." }
        bundle = ([other_pages.first.to_s, short_note] + other_pages.drop(1)).map { |p| "#{p}\f\n" }.join

        entries = described_class.call(bundle)

        expect(entries.length).to eq(6)
        expect(entries[1].text).to start_with("Dear Council,\nPlease vote yes")
      end

      it "does not suppress a subsequent From: email when a preceding constituent letter ends with Date: or To:" do
        first_letter = <<~TXT
          From: First Resident <first@example.com>
          Sent: Wednesday, October 14, 2026 5:00 PM
          To: City Council <council@baltimorecity.gov>
          Subject: Support for Bill 169

          Dear Council Members,
          I am writing in strong support of Bill 169 for our neighborhood.
          Thank you for your consideration.
          Jane Resident
          Date: October 14, 2026
        TXT
        second_letter = <<~TXT
          From: Second Resident <second@example.com>
          Sent: Thursday, October 15, 2026 9:00 AM
          To: City Council <council@baltimorecity.gov>
          Subject: Oppose Bill 169

          Dear Council Members,
          I oppose this bill.
        TXT
        bundle = "#{first_letter}\n#{second_letter}"

        entries = described_class.call(bundle)

        expect(entries.length).to eq(2)
        expect(entries.first.text).to start_with("From: First Resident")
        expect(entries.last.text).to start_with("From: Second Resident")
      end

      it "splits a 1-page From: cover email ending with a closing sign-off right before a >= 6-page report appendix" do
        email_page = "From: Sender <sender@example.com>\nSubject: Testimony\n\nDear Council,\nI urge a favorable report.\nSincerely,\nJane Doe"
        extra_pages = [
          "EXECUTIVE SUMMARY\nOverview of corridor conditions."
        ] + (2..6).map { |n| "Part #{n} of corridor study with detailed tables." }
        bundle = ([email_page] + extra_pages).map { |p| "#{p}\f\n" }.join

        entries = described_class.call(bundle)

        expect(entries.length).to eq(2)
        expect(entries.first.text).to start_with("From: Sender")
        expect(Testimony::ExtractedText.effective_page_count(entries.first.text)).to eq(1)
        expect(entries.last.text).to start_with("EXECUTIVE SUMMARY")
        expect(Testimony::ExtractedText.over_constituent_page_limit?(entries.last.text)).to be true
        expect(entries.map(&:text).join).to eq(bundle)
      end

      it "detaches a > 5-page report appendix after a constituent letter inside a non-From: multi-letter packet" do
        letter_one = "Dear Council President and Members,\nI support this legislation for our block."
        letter_two = "Dear Council Members,\nPlease see the attached report on corridor safety.\nSincerely,\nJane Doe"
        report_pages = [
          "EXECUTIVE SUMMARY\nCorridor safety findings."
        ] + (2..6).map { |n| "Section #{n} of the corridor safety report with tables." }
        bundle = ([letter_one, letter_two] + report_pages).map { |p| "#{p}\f\n" }.join

        entries = described_class.call(bundle)

        expect(entries.length).to eq(3)
        expect(entries[0].text).to start_with("Dear Council President")
        expect(entries[1].text).to start_with("Dear Council Members,\nPlease see the attached report")
        expect(Testimony::ExtractedText.effective_page_count(entries[1].text)).to eq(1)
        expect(entries[2].text).to start_with("EXECUTIVE SUMMARY")
        expect(Testimony::ExtractedText.over_constituent_page_limit?(entries[2].text)).to be true
        expect(entries.map(&:text).join).to eq(bundle)
      end

      it "does not split an agency memo with a > 4-line letterhead above Date:/To:/From:/Re: when MEMORANDUM is absent" do
        memo = <<~TXT
          CITY OF BALTIMORE
          Brandon M. Scott, Mayor
          DEPARTMENT OF PLANNING
          Chris Ryer, Director
          417 E. Fayette Street, 8th Floor
          Baltimore, Maryland 21202

          Date: October 15, 2026
          To: The Honorable President and Members of the Baltimore City Council
          From: Department of Planning
          Re: City Council Bill 26-0093

          The Department of Planning is herein reporting on City Council Bill 26-0093.
        TXT

        entries = described_class.call(memo)

        expect(entries.length).to eq(1)
        expect(entries.first.text).to eq(memo)
      end
    end
  end
end
