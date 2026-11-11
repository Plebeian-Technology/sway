# frozen_string_literal: true

require "rails_helper"
require "support/testimony_fixtures"

# Reads one letter's sender through a window of
# lines rather than one line, because most real letters carry the address on
# a line after the marker.
RSpec.describe Testimony::SenderReader do
  describe ".call" do
    it "reads an address that sits on the same line as the marker" do
      text = "From: Alex Example <alexexample1@everyactioncustom.com>\n" \
        "Sent: Monday, June 2, 2026 2:01 PM\nTo: City Council <citycouncil@baltimorecity.gov>\n"

      result = described_class.call(text)

      expect(result.address).to eq("alexexample1@everyactioncustom.com")
      expect(result.domain).to eq("everyactioncustom.com")
    end

    it "reads a value on a following line when the marker is alone on its own line" do
      text = "From:\nSam Example <samexample12@everyactioncustom.com>\n" \
        "Sent: Monday, June 13, 2026 1:12 AM\nTo: City Council <citycouncil@baltimorecity.gov>\n"

      result = described_class.call(text)

      expect(result.address).to eq("samexample12@everyactioncustom.com")
      expect(result.domain).to eq("everyactioncustom.com")
    end

    it "reads an address that wraps at the at-sign as one address, not a bare local part or a bare domain" do
      text = "From: Jordan Example <jordanexample21\n@everyactioncustom.com>\n" \
        "Sent: Monday, June 22, 2026 10:21 PM\nTo: City Council <citycouncil@baltimorecity.gov>\n"

      result = described_class.call(text)

      expect(result.address).to eq("jordanexample21@everyactioncustom.com")
      expect(result.domain).to eq("everyactioncustom.com")
    end

    it "reads the fixture's own wrapped-address letter the same way, through the real letter splitter" do
      wrapped_entry = Testimony::LetterSplitter.call(TestimonyFixtures.campaign_bundle)
        .find { |letter| letter.text.match?(TestimonyFixtures::WRAPPED_ADDRESS) }

      # #find returns an Entry?, which Steep cannot narrow with a raise or an
      # RSpec matcher — chaining
      # &.text.to_s keeps the call typed String without a nil guard.
      result = described_class.call(wrapped_entry&.text.to_s)

      expect(result.address).to eq(TestimonyFixtures.wrapped_sender_address)
      expect(result.domain).to eq("everyactioncustom.com")
    end

    it "lower-cases the domain and strips trailing punctuation" do
      text = "From: jane@EXAMPLE.COM.\nSent: Monday.\n"

      result = described_class.call(text)

      expect(result.domain).to eq("example.com")
    end

    it "yields no address and no domain for a letter with no sender marker at all" do
      text = "Dear Council,\nI support this bill for my own reasons.\n"

      result = described_class.call(text)

      expect(result.address).to be_nil
      expect(result.domain).to be_nil
    end

    it "does not look past the declared window, so an address far beyond it is never found" do
      filler = (["filler line, no address here"] * (Testimony::SenderReader::WINDOW_LINES + 5)).join("\n")
      text = "From:\n#{filler}\nreal@example.com\n"

      result = described_class.call(text)

      expect(result.address).to be_nil
    end

    # B4. ADDRESS_TOKEN requires a dot in the domain part, so a bare local
    # part with nothing after the "@" no longer looks address-shaped at all —
    # there is nothing here worth keeping as evidence of who wrote the letter.
    it "yields no address and no domain for a token with nothing after the @" do
      result = described_class.call("From: a@\n\n\n")

      expect(result.address).to be_nil
      expect(result.domain).to be_nil
    end

    it "yields no address and no domain when the marker's own line ends at the @" do
      result = described_class.call("From:\ncontact@\n\n")

      expect(result.address).to be_nil
      expect(result.domain).to be_nil
    end

    # CR-02/WR-05. ADDRESS_TOKEN is deliberately not a full grammar beyond
    # requiring the dot — it accepts whatever survived the document
    # conversion — so the DOMAIN it yields still needs its own contract, or
    # 253+ characters of anything reaches SendingServiceDomain, which
    # validates presence only.
    #
    # That contract governs the DOMAIN only (B4). These examples assert the
    # domain is refused AND the address is kept, because the two questions
    # have different owners and folding them into one nil erased senders.
    # B4. The domain contract says what may become a globally unique row. It
    # does not say whether a letter has a sender — and folding the two into
    # one nil turned "this domain is odd" into "nobody sent this letter",
    # which is the third piece of evidence
    # Testimony::SourceKindRules needs to read a person as speaking for an
    # organization. An underscore is refused by the format and is an ordinary
    # thing to survive a document conversion.
    it "keeps the address when the domain fails the storage contract" do
      result = described_class.call("From: jane@exa_mple.com\nI write on behalf of the Coalition.\n")

      expect(result.address).to eq("jane@exa_mple.com")
      expect(result.domain).to be_nil
    end

    it "keeps an address whose domain is far longer than a domain name can be" do
      result = described_class.call("From: a@#{"x" * 300}.com\n\n")

      expect(result.address).to eq("a@#{"x" * 300}.com")
      expect(result.domain).to be_nil
    end

    it "yields no domain for a run far longer than a domain name can be" do
      result = described_class.call("From: a@#{"x" * 300}.com\n\n")

      expect(result.domain).to be_nil
    end

    it "yields no domain for a run that is not shaped like a domain name" do
      result = described_class.call("From: a@%%%.!!!\n\n")

      expect(result.domain).to be_nil
    end

    # B4. Every real mail header puts To: a line or two below From:, and
    # nothing about the window previously said a token it found still
    # belonged to the From: field — it read the City Council's own address
    # off the To: line as if the letter's author had sent it. Measured
    # against a letter shaped exactly like the review found (67-REVIEW.md B4).
    it "stops the window at the next header field, so a later To: address is never read as the sender" do
      text = "From: Jane Doe\nSent: Monday, June 2, 2026 2:01 PM\n" \
        "To: City Council <citycouncil@baltimorecity.gov>\n\n" \
        "Jane Doe\nExecutive Director of the Baltimore Housing Coalition\n"

      result = described_class.call(text)

      expect(result.address).to be_nil
      expect(result.domain).to be_nil
    end

    # B4. The window used to join the whole slice before matching a token, so
    # ordinary prose containing an "@" invented an address and a domain that
    # passed the format check — "5pm" has no dot but still matches
    # Testimony::SenderDomain::FORMAT, and would have become a permanent
    # global row from a line of a public PDF.
    it "does not invent an address out of prose that merely contains an at-sign" do
      text = "From:\nJane Doe\nMeeting @ 5pm at the hall\nTo: council\n"

      result = described_class.call(text)

      expect(result.address).to be_nil
      expect(result.domain).to be_nil
    end

    it "gives the same answer reading the same letter twice" do
      text = "From: Alex Example <alexexample1@everyactioncustom.com>\nSent: Monday, June 2, 2026 2:01 PM\n"

      expect(described_class.call(text)).to eq(described_class.call(text))
    end
  end
end
