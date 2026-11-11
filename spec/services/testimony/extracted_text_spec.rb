# frozen_string_literal: true

require "rails_helper"

RSpec.describe Testimony::ExtractedText do
  describe ".header_line_pattern" do
    it "matches the phrase only at the start of a line, not mid-line" do
      pattern = described_class.header_line_pattern("From:")

      expect(pattern.match?("From: Jane Doe\n")).to be true
      expect(pattern.match?("Dear Council,\n> From: someone else")).to be false
    end

    it "matches after any newline, not only at the very start of the text" do
      pattern = described_class.header_line_pattern("From:")

      expect(pattern.match?("A cover note.\nFrom: Jane Doe\n")).to be true
    end

    it "consumes the run of spaces or tabs after the phrase" do
      pattern = described_class.header_line_pattern("From:")

      expect(pattern.match("From:\t\t Jane Doe").to_s).to eq("From:\t\t ")
    end

    it "is byte-identical to the marker LetterSplitter and SenderReader each build from it, pinning the single definition" do
      expect(Testimony::LetterSplitter::LETTER_MARKER).to eq(Testimony::SenderReader::SENDER_MARKER)
      expect(Testimony::LetterSplitter::LETTER_MARKER.source).to eq(described_class.header_line_pattern("From:").source)
    end
  end

  describe ".header_line?" do
    it "is true when the text's own opening is the header line" do
      expect(described_class.header_line?("From: Jane Doe\nDear Council,", "From:")).to be true
    end

    it "is false when the header opens a later line rather than the text's own first" do
      text = "Dear Council,\nFrom: someone else"

      expect(described_class.header_line_pattern("From:").match?(text)).to be true
      expect(described_class.header_line?(text, "From:")).to be false
    end

    it "is false for nil or blank text" do
      expect(described_class.header_line?(nil, "From:")).to be false
      expect(described_class.header_line?("", "From:")).to be false
    end
  end

  describe ".envelope_field_line?" do
    it "is true for a real mail header field" do
      expect(described_class.envelope_field_line?("From: Jane Doe <jane@example.com>")).to be true
      expect(described_class.envelope_field_line?("Subject: Support for Bill X")).to be true
    end

    it "is false for a line that only looks like the generic field shape" do
      expect(described_class.envelope_field_line?("CAUTION: This email originated from outside.")).to be false
      expect(described_class.envelope_field_line?("Reminder: DO NOT click links.")).to be false
    end
  end

  describe ".strip_envelope" do
    it "drops a clean four-line envelope, stopping right after Subject:" do
      text = "From: Jane Doe <jane@example.com>\nSent: Monday\nTo: City Council <citycouncil@example.gov>\n" \
        "Subject: Support for Bill X\n\nDear Council Members,\n\nbody text\n"

      stripped = described_class.strip_envelope(text)

      expect(stripped).to include("Dear Council Members,").and include("body text")
      expect(stripped).not_to include("From:")
      expect(stripped).not_to include("Subject:")
    end

    it "drops the envelope across a blank line inside it, when the next non-blank line is also a field" do
      text = "From: Jane Doe <jane@example.com>\nSent: Monday\n\nTo: City Council <citycouncil@example.gov>\n" \
        "Subject: Support for Bill X\n\nDear Council,\n\nbody text\n"

      stripped = described_class.strip_envelope(text)

      expect(stripped).not_to include("To: City Council")
      expect(stripped).to include("Dear Council,")
    end

    it "keeps the letter's own opening line when no blank line separates it from Subject:" do
      text = "From: Jane Doe <jane@example.com>\nSubject: Support for Bill X\nDear Council Members,\n\nI am writing...\n"

      stripped = described_class.strip_envelope(text)

      expect(stripped).to start_with("Dear Council Members,")
    end

    it "does not cross a blank line whose next non-blank line is not a field — the city IT banner is never treated as envelope" do
      text = "From: Jane Doe <jane@example.com>\n\nCAUTION: banner text\nReminder: banner text\n\nDear Council,\n\nbody\n"

      stripped = described_class.strip_envelope(text)

      expect(stripped).to include("CAUTION: banner text")
    end

    it "strips nothing when the text opens with prose rather than a field" do
      text = "Dear Council,\n\nI support this bill."

      expect(described_class.strip_envelope(text)).to eq(text)
    end

    it "drops multiline unindented To: and Cc: headers across PDF margin wraps" do
      text = <<~TXT
        From: Jane Resident <jane@example.com>
        To: rdorsey <Ryan.Dorsey@baltimorecity.gov>; Cohen, Zeke (City Council) <Zeke.Cohen@baltimorecity.gov>; McCray, 
        Danielle (City Council) <Danielle.McCray@baltimorecity.gov>; Parker, Mark (City Council) 
        <mark.parker@baltimorecity.gov>; Conway, Mark (City Council) <Mark.Conway@baltimorecity.gov>; 
        Cc: Brandon M Scott <brandonm.scott@baltimorecity.gov> 
        Subject: Support for Bill 169

        Dear Council Members,

        I am writing in strong support of Bill 169.
      TXT

      stripped = described_class.strip_envelope(text)

      expect(stripped).to start_with("Dear Council Members,")
      expect(stripped).not_to include("Danielle.McCray@baltimorecity.gov")
      expect(stripped).not_to include("brandonm.scott@baltimorecity.gov")
    end

    it "drops an envelope whose fields have their values on a new unindented line" do
      text = <<~TXT
        From:
        Cohen, Zeke (City Council)
        Sent:
        Thursday, October 15, 2026 8:57 AM
        To:
        Testimony
        Subject:
        Fw: Harford Road Overlay

        Dear Council,
        I am writing.
      TXT

      stripped = described_class.strip_envelope(text)

      expect(stripped).to start_with("Dear Council,")
      expect(stripped).not_to include("Cohen, Zeke")
      expect(stripped).not_to include("Fw: Harford Road Overlay")
    end
    it "does not swallow an opening prose sentence containing commas and 'Council' when Subject: and blank lines are absent" do
      text = <<~TXT
        From: Jane Resident <jane@example.com>
        To: Zeke.Cohen@baltimorecity.gov
        As a resident of Harford Road, I am writing to ask the City Council to pass Bill 169.
        In my neighborhood, small businesses need this overlay, and the council should act now.
      TXT

      stripped = described_class.strip_envelope(text)

      expect(stripped).to start_with("As a resident of Harford Road,")
      expect(stripped).to include("In my neighborhood, small businesses need this overlay")
    end

    it "strips an envelope preceded by leading form-feeds, blank lines, or a forward/reply divider line" do
      text = "\f\n\n-----Original Message-----\nFrom: Jane Resident <jane@example.com>\nSent: Monday\nSubject: Support\n\nDear Council,\nI support this bill."

      stripped = described_class.strip_envelope(text)

      expect(stripped).to eq("Dear Council,\nI support this bill.")
    end

    it "strips an envelope preceded by a folded page-number and clerk print-header stub" do
      text = "1\nClerk Name (City Council)\n\nFrom: Jane Resident <jane@example.com>\nSent: Monday\nSubject: Support\n\nDear Council,\nI support this bill."

      stripped = described_class.strip_envelope(text)

      expect(stripped).to eq("Dear Council,\nI support this bill.")
    end

    it "strips a trailing folded clerk print-header stub page so it does not leak into campaign added_words or duplicate body hashes" do
      text = "From: Jane Resident <jane@example.com>\nSent: Monday\nSubject: Support\n\nDear Council,\nI support this bill.\f\n\n\n2\nLeva, Anthony F. (City Council)\n"

      stripped = described_class.strip_envelope(text)

      expect(stripped).to eq("Dear Council,\nI support this bill.")
      expect(stripped).not_to include("Leva, Anthony F.")
    end
  end

  describe ".starts_with_from_header?" do
    it "returns true for a direct From: header or one preceded by a clerk print-header stub" do
      expect(described_class.starts_with_from_header?("From: Jane <jane@example.com>\nDear Council,")).to be true
      expect(described_class.starts_with_from_header?("1\nClerk Name (City Council)\n\nFrom: Jane <jane@example.com>\nDear Council,")).to be true
      expect(described_class.starts_with_from_header?("Dear Council,\nI support this bill.")).to be false
    end
  end

  describe ".strip_recipient_headers" do
    it "removes multiline To: and Cc: headers while preserving From: and Subject:" do
      text = <<~TXT
        From: Jane Resident <jane@example.com>
        Sent: Wednesday, October 14, 2026 5:00 PM
        To: rdorsey <Ryan.Dorsey@baltimorecity.gov>; Cohen, Zeke (City Council) <Zeke.Cohen@baltimorecity.gov>; McCray, 
        Danielle (City Council) <Danielle.McCray@baltimorecity.gov>; Parker, Mark (City Council) 
        <mark.parker@baltimorecity.gov>; Conway, Mark (City Council) <Mark.Conway@baltimorecity.gov>; 
        Cc: Brandon M Scott <brandonm.scott@baltimorecity.gov> 
        Subject: Harford Road Overlay

        Dear Council Members,
        I am writing to support...
      TXT

      result = described_class.strip_recipient_headers(text)

      expect(result).to include("From: Jane Resident <jane@example.com>")
      expect(result).to include("Subject: Harford Road Overlay")
      expect(result).to include("Dear Council Members,")
      expect(result).not_to include("Ryan.Dorsey@baltimorecity.gov")
      expect(result).not_to include("Danielle.McCray@baltimorecity.gov")
      expect(result).not_to include("brandonm.scott@baltimorecity.gov")
    end

    it "removes To: headers whose value sits on the next unindented line" do
      text = <<~TXT
        From:
        Cohen, Zeke (City Council)
        Sent:
        Thursday, October 15, 2026 8:57 AM
        To:
        Testimony
        Subject:
        Fw: Harford Road Overlay

        Dear Council,
        I support this bill.
      TXT

      result = described_class.strip_recipient_headers(text)

      expect(result).not_to include("To:")
      expect(result).not_to include("Testimony")
      expect(result).to include("Subject:\nFw: Harford Road Overlay")
      expect(result).to include("Dear Council,")
    end

    it "preserves constituent prose sentences containing commas and 'Council' immediately after To: and mid-body lines starting with To:" do
      text = <<~TXT
        From: Jane Resident <jane@example.com>
        To: Zeke.Cohen@baltimorecity.gov
        As a resident of Harford Road, I am writing to ask the City Council to pass Bill 169.

        To: the point raised at Tuesday's hearing, our block association disagrees with the council staff report.
      TXT

      result = described_class.strip_recipient_headers(text)

      expect(result).not_to include("Zeke.Cohen@baltimorecity.gov")
      expect(result).to include("As a resident of Harford Road, I am writing to ask the City Council to pass Bill 169.")
      expect(result).to include("To: the point raised at Tuesday's hearing, our block association disagrees with the council staff report.")
    end
  end

  # W-02: the only signal that distinguishes a forwarded
  # header from an original one, since both sit at column zero preceded by a
  # blank line.
  describe ".forward_or_reply_marker?" do
    it "is true for an Outlook-style bare underscore rule" do
      expect(described_class.forward_or_reply_marker?(["reply text", "________________________________"])).to be true
    end

    it "is false for a bare dash rule — this codebase's own testimony bundles use one as an ordinary letter divider" do
      expect(described_class.forward_or_reply_marker?(["reply text", "----------------------------------------"])).to be false
    end

    it "is true for '-----Original Message-----', tolerant of dash count and case" do
      expect(described_class.forward_or_reply_marker?(["---original message---"])).to be true
    end

    it "is true for '---------- Forwarded message ----------'" do
      expect(described_class.forward_or_reply_marker?(["---------- Forwarded message ----------"])).to be true
    end

    it "is true for 'Begin forwarded message:'" do
      expect(described_class.forward_or_reply_marker?(["Begin forwarded message:"])).to be true
    end

    it "is true for 'On <date> ... wrote:'" do
      expect(described_class.forward_or_reply_marker?(["On Mon, Jun 2, 2026 at 3:00 PM, John Doe <john@example.com> wrote:"])).to be true
    end

    it "is true for 'On ... wrote:' wrapped across two extracted lines" do
      lines = ["On Mon, Jun 2, 2026 at 3:00 PM, John", "Doe <john@example.com> wrote:"]

      expect(described_class.forward_or_reply_marker?(lines)).to be true
    end

    it "is false for ordinary letter text" do
      expect(described_class.forward_or_reply_marker?(["Thank you,", "Jane Doe", "100 Example Street"])).to be false
    end
  end

  describe ".print_header_stub?" do
    it "is true for blank text or a short 1-3 line print header stub with no sentence punctuation, including middle initials" do
      expect(described_class.print_header_stub?("")).to be true
      expect(described_class.print_header_stub?("1\nLeva, Anthony F (City Council)\n")).to be true
      expect(described_class.print_header_stub?("1\nLeva, Anthony F. (City Council)\n")).to be true
    end

    it "is false for a sentence carrying punctuation or longer body text" do
      expect(described_class.print_header_stub?("I support this bill.")).to be false
      expect(described_class.print_header_stub?("A" * 90)).to be false
    end

    it "is false for a short constituent note opening with a greeting, From: header, or stance keywords even without sentence punctuation" do
      expect(described_class.print_header_stub?("Dear Council,\nPlease vote yes\nJane Doe")).to be false
      expect(described_class.print_header_stub?("From: jane@example.com\nVote yes")).to be false
      expect(described_class.print_header_stub?("Position: Support\nPlease pass Bill 169\nJane Doe")).to be false
    end
  end

  describe ".effective_page_count and .over_constituent_page_limit?" do
    it "counts non-empty form-feed pages and ignores print-header stub pages" do
      five_pages = (1..5).map { |n| "Page #{n} body with full sentences." }.join("\f\n")
      with_stubs = "1\nLeva, Anthony F (City Council)\n\f\n#{five_pages}\f\n6\nLeva, Anthony F (City Council)\n"

      expect(described_class.effective_page_count(five_pages)).to eq(5)
      expect(described_class.effective_page_count(with_stubs)).to eq(5)
      expect(described_class.over_constituent_page_limit?(with_stubs)).to be false
    end

    it "flags text with more than five effective pages as over the constituent page limit" do
      six_pages = (1..6).map { |n| "Page #{n} body with full sentences." }.join("\f\n")

      expect(described_class.effective_page_count(six_pages)).to eq(6)
      expect(described_class.over_constituent_page_limit?(six_pages)).to be true
    end
  end

  describe ".unwrap_body_paragraphs" do
    it "keeps an opening salutation on line 1 while unwrapping ragged PDF-wrapped prose lines into a single paragraph" do
      text = "Mayor Scott- and Coucilman \n" \
        "I live along side of the proposed Overlay Bill. Our District Coucilman Mr Dorsey-has written a Bill that \n" \
        "is going \n" \
        "to affect my community, Lauraville. Going up the first block 500' from Harford Road. Thats estimating \n" \
        "5 houses on BOTH sides \n" \
        "a total of 10. Lauraville isn't a large community. Its small and retains its family orientated community. "

      expect(described_class.unwrap_body_paragraphs(text)).to eq(
        "Mayor Scott- and Coucilman\n" \
        "I live along side of the proposed Overlay Bill. Our District Coucilman Mr Dorsey-has written a Bill that " \
        "is going to affect my community, Lauraville. Going up the first block 500' from Harford Road. Thats estimating " \
        "5 houses on BOTH sides a total of 10. Lauraville isn't a large community. Its small and retains its family orientated community."
      )
    end

    it "collapses artificial double-spacing across mid-sentence wrapped lines while preserving real paragraph breaks" do
      text = "My name is Kyle Long. I am \n\n" \
        "submitting this testimony in support of Council Bill 25-0036-\n\n" \
        "Task Force.\n\n" \
        "This is a second paragraph that starts after terminal punctuation."

      expect(described_class.unwrap_body_paragraphs(text)).to eq(
        "My name is Kyle Long. I am submitting this testimony in support of Council Bill 25-0036- Task Force.\n\n" \
        "This is a second paragraph that starts after terminal punctuation."
      )
    end

    it "preserves line breaks for bullet lists and closing sign-off blocks" do
      text = "Dear Council Members,\n" \
        "I urge you to pass this bill for three reasons:\n" \
        "- Safe streets for pedestrians\n" \
        "- Better transit access\n" \
        "1. Protected bike lanes\n" \
        "Sincerely,\n" \
        "Jane Resident\n" \
        "District 3"

      expect(described_class.unwrap_body_paragraphs(text)).to eq(
        "Dear Council Members,\n" \
        "I urge you to pass this bill for three reasons:\n" \
        "- Safe streets for pedestrians\n" \
        "- Better transit access\n" \
        "1. Protected bike lanes\n" \
        "Sincerely,\n" \
        "Jane Resident\n" \
        "District 3"
      )
    end

    it "strips zero-width characters and unwraps sentences across mid-letter form-feed page breaks" do
      text = "Dear Council,\n\u200bI am writing to urge a favorable report on \n2\n\f\n1\nLeva, Anthony F (City Council)\n\f\nthe proposed ordinance."

      expect(described_class.unwrap_body_paragraphs(text)).to eq(
        "Dear Council,\nI am writing to urge a favorable report on the proposed ordinance."
      )
    end

    it "unwraps mid-sentence lines starting with 'respectfully ask...', 'thank you for...', 'Mayor Scott and...', or 'testimony on this bill...'" do
      text = "Dear Council,\n" \
        "We urge the committee to hear our neighborhood concerns and\n" \
        "respectfully ask that you vote against this bill,\n" \
        "which would harm our block. We also\n" \
        "thank you for holding this evening hearing so working residents can attend.\n" \
        "Earlier this year,\n" \
        "Mayor Scott and the Department of Housing promised community input, and\n" \
        "testimony on this bill shows why residents are concerned."

      expect(described_class.unwrap_body_paragraphs(text)).to eq(
        "Dear Council,\n" \
        "We urge the committee to hear our neighborhood concerns and respectfully ask that you vote against this bill, " \
        "which would harm our block. We also thank you for holding this evening hearing so working residents can attend. " \
        "Earlier this year, Mayor Scott and the Department of Housing promised community input, and testimony on this bill shows why residents are concerned."
      )
    end
  end
end
