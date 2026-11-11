# frozen_string_literal: true

require "rails_helper"
require "support/testimony_fixtures"

# The whole seam — extracted testimony in, a cleaned artifact out, the
# positions prompt reading that artifact instead of the raw column.
RSpec.describe Testimony::CharacterRepair do
  describe ".call" do
    it "repairs a break with a letter on both sides, using a spelling already unbroken elsewhere in the same text" do
      result = described_class.call("We support Bal\u{FFFD}more's plan. Baltimore needs it.")

      expect(result.text).to eq("We support Baltimore's plan. Baltimore needs it.")
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(1)
      expect(result.resolved_by_fallback).to eq(0)
      expect(result.left_unresolved).to eq(0)
    end

    # A second extraction run writes "$" for the same broken
    # ligature U+FFFD stands in for elsewhere — measured, 363 of 6,781 breaks
    # across the ten stored attachment files. Resolved the same way as a
    # U+FFFD break: only against a spelling the same text already carries.
    it "repairs a '$' break the same way as a U+FFFD break, using a spelling already unbroken elsewhere" do
      result = described_class.call("The committee voted on the kitten shelter funding. The ki$en shelter needs support.")

      expect(result.text).to include("The kitten shelter needs support.")
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(1)
      expect(result.resolved_by_fallback).to eq(0)
      expect(result.left_unresolved).to eq(0)
    end

    # "$" is a real character — 18 of 381 in the ten stored files are
    # genuine currency — so, unlike U+FFFD, an ambiguous "$" break is never
    # guessed at. Left exactly as it arrived instead.
    it "leaves an ambiguous '$' break unresolved rather than guessing, unlike an ambiguous U+FFFD break" do
      text = "The fo$bar arrangement was discussed at length."

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(0)
      expect(result.resolved_by_fallback).to eq(0)
      expect(result.left_unresolved).to eq(1)
    end

    it "leaves a genuine dollar amount untouched — a digit on one side is never a candidate for repair" do
      text = "The contract was worth $5 million to the city."

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.broken_words).to eq(0)
      expect(result.left_unresolved).to eq(0)
    end

    # B5 seeds the vocabulary from CITY_IT_BANNER's own words, so a broken
    # word that reconstructs to one of THOSE words (e.g. "activities") now
    # resolves from the seed even alone in a short sentence — this example
    # uses "priorities" instead, a word CITY_IT_BANNER never carries, to keep
    # testing the case where nothing corroborates the guess at all.
    it "falls back to the declared fallback pair when no candidate is found unbroken elsewhere" do
      result = described_class.call("Report any suspicious priori\u{FFFD}es today.")

      expect(result.text).to eq("Report any suspicious priorities today.")
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(0)
      expect(result.resolved_by_fallback).to eq(1)
      expect(result.left_unresolved).to eq(0)
    end

    it "falls back, never first-wins, when more than one candidate is found unbroken elsewhere" do
      text = "The fotibar arrived on time. The fottbar left early. We saw the fo\u{FFFD}bar today."

      result = described_class.call(text)

      expect(result.text).to end_with("We saw the fotibar today.")
      expect(result.broken_words).to eq(1)
      expect(result.resolved_from_bundle).to eq(0)
      expect(result.resolved_by_fallback).to eq(1)
      expect(result.left_unresolved).to eq(0)
    end

    it "leaves a replacement character alone at the very start of the text" do
      text = "\u{FFFD}more people arrived than expected."

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.broken_words).to eq(0)
    end

    it "leaves a replacement character alone at the very end of the text" do
      text = "the whole crowd came out for Bal\u{FFFD}"

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.broken_words).to eq(0)
    end

    it "leaves a replacement character alone with a space on either side" do
      text = "the sign read Support \u{FFFD} Oppose on the ballot"

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.broken_words).to eq(0)
    end

    it "leaves two adjacent replacement characters alone — there is no letter between them" do
      text = "the word came out as wo\u{FFFD}\u{FFFD}rd on the page"

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.broken_words).to eq(0)
    end

    # @lat: [[testimony-letters#A broken glyph is recorded rather than repaired]]
    it "counts a literal question mark between two letters as an unresolved break and does not rewrite it" do
      text = "Do you support this bill?Yes I do."

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.broken_words).to eq(1)
      expect(result.left_unresolved).to eq(1)
      expect(result.resolved_by_fallback).to eq(0)
    end

    it "passes text with no replacement character through byte for byte, every count zero" do
      text = "Plain testimony with no broken characters at all."

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.broken_words).to eq(0)
      expect(result.resolved_from_bundle).to eq(0)
      expect(result.resolved_by_fallback).to eq(0)
      expect(result.left_unresolved).to eq(0)
    end
  end
end

RSpec.describe Testimony::BoilerplateRemover do
  describe ".call" do
    # The same words, wrapped where the other extraction run wrapped them:
    # the break after "know that" instead of after "safe.", and the third
    # sentence beginning on the same line as the second one ends.
    let(:banner_wrapped_elsewhere) do
      "CAUTION:  This email originated from outside of Baltimore City IT Network Systems.   \n" \
        "Reminder:  DO NOT click links or open attachments unless you recognize the sender and know that \n" \
        "the content is safe.  Report any suspicious activities using the Report Phishing Email Button, or by \n" \
        "emailing to Phishing@baltimorecity.gov "
    end
    # @lat: [[testimony-letters#Fixtures for extracted text are typed by hand]]
    let(:banner_with_trailing_spaces) do
      "CAUTION:  This email originated from outside of Baltimore City IT Network Systems.  \n" \
        "Reminder:  DO NOT click links or open attachments unless you recognize the sender and know that the content is safe.  \n" \
        "Report any suspicious activities using the Report Phishing Email Button, or by emailing to Phishing@baltimorecity.gov "
    end

    it "removes a single occurrence of the banner and counts its characters" do
      text = "Dear Council,\n\n#{described_class::CITY_IT_BANNER}\n\nI support this bill.\n"

      result = described_class.call(text)

      expect(result.text).not_to include("This email originated from outside of")
      expect(result.occurrences).to eq(1)
      expect(result.characters_removed).to eq(described_class::CITY_IT_BANNER.length)
    end

    it "removes every occurrence in a bundle of several letters" do
      one_letter = "Dear Council,\n\n#{described_class::CITY_IT_BANNER}\n\nI support this bill.\n"
      text = ([one_letter] * 3).join("\n----\n")

      result = described_class.call(text)

      expect(result.occurrences).to eq(3)
      expect(result.text.scan("This email originated from outside of").length).to eq(0)
    end

    it "passes a bundle with no banner through unchanged, zero occurrences" do
      text = "Dear Council,\n\nI support this bill for my own reasons.\n"

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.occurrences).to eq(0)
      expect(result.characters_removed).to eq(0)
    end

    it "removes the banner when every line carries the trailing spaces real extracted text carries" do
      text = "Dear Council,\n\n#{banner_with_trailing_spaces}\n\nI support this bill.\n"

      result = described_class.call(text)

      expect(result.occurrences).to eq(1)
      expect(result.text).not_to include("This email originated from outside of")
      expect(result.characters_removed).to be > 0
    end

    it "removes the banner when the line breaks fall in different places than the constant's" do
      text = "Dear Council,\n\n#{banner_wrapped_elsewhere}\n\nI oppose this bill.\n"

      result = described_class.call(text)

      expect(result.occurrences).to eq(1)
      expect(result.text).not_to include("Report any suspicious activities")
    end

    it "counts the characters it actually removed, not the constant's own length" do
      text = "Dear Council,\n\n#{banner_wrapped_elsewhere}\n\nI oppose this bill.\n"

      result = described_class.call(text)

      expect(result.characters_removed).to be > 0
      expect(result.characters_removed).to eq(text.length - result.text.length)
      expect(result.characters_removed).not_to eq(described_class::CITY_IT_BANNER.length)
    end

    it "preserves a formal inside-address block addressed to 'The Honorable ...' rather than stripping it as a municipal office footer" do
      text = <<~TXT
        The Honorable Zeke Cohen
        President, Baltimore City Council
        100 N. Holliday Street, Suite 400
        Baltimore, MD 21202

        Dear President Cohen,
        I support this bill.
      TXT

      result = described_class.call(text)

      expect(result.text).to eq(text)
      expect(result.occurrences).to eq(0)
    end

    it "removes a forward wrapper whose body consists only of a 2-line wrapped 'On ... wrote:' quote marker" do
      wrapper = <<~TXT
        From: Staffer <staffer@baltimorecity.gov>
        Sent: Friday, October 16, 2026 10:00 AM
        To: Testimony
        Subject: Fw: Constituent testimony

        On Thu, Oct 15, 2026 at 4:15 PM Jane Resident
        <jane@example.com> wrote:

      TXT
      constituent = <<~TXT
        From: Jane Resident <jane@example.com>
        Sent: Thursday, October 15, 2026 4:15 PM
        To: Staffer <staffer@baltimorecity.gov>
        Subject: Constituent testimony

        Dear Council,
        I support this bill.
      TXT

      result = described_class.call("#{wrapper}#{constituent}")

      expect(result.text).to eq(constituent)
      expect(result.occurrences).to eq(1)
    end
  end
end

RSpec.describe Testimony::CleanAndGroupService do
  let(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "Maryland", country: "United States") }
  let(:bill) do
    create(:bill, sway_locale: sway_locale, external_id: "HB9999", title: "An act concerning transit")
  end

  describe "the two fixtures" do
    # Without this, a stage that silently stopped reading either fixture
    # would make both fixture-dependent examples pass for the wrong reason
    # (Pattern 9 in 67-PATTERNS.md).
    it "differ in the expected place — the campaign bundle carries a sending-service domain, the control does not" do
      expect(TestimonyFixtures.campaign_bundle).to include("everyactioncustom.com")
      expect(TestimonyFixtures.no_campaign_bundle).not_to include("everyactioncustom.com")
    end

    it "both carry the city IT banner, so a banner-only removal cannot be mistaken for campaign detection" do
      expect(TestimonyFixtures.campaign_bundle).to include("This email originated from outside of")
      expect(TestimonyFixtures.no_campaign_bundle).to include("This email originated from outside of")
    end
  end

  # "not too eager" fails in two opposite
  # directions, so it needs two different checks. This is the one that holds
  # on EVERY bill, including a bill added later: wherever the stage marks
  # zero letters campaign-origin, the cleaned text must be reachable by
  # applying ONLY the repair and the banner removal to the raw text — nothing
  # else. Expressed as a RECONSTRUCTION, not a count, because a count-based
  # check ("N characters removed") would pass for a stage that removed the
  # wrong characters in the right quantity — the same trap
  # spec/services/bill_summary_prompt_builder_spec.rb's own "differ in the
  # expected place" example (~line 992) exists to catch for a builder that
  # silently stopped rendering a section.
  #
  # A stage that does nothing at all would satisfy this alone — see the "the
  # two fixtures... differ" example above for the other half of the proof.
  describe "the not-too-eager invariant: where nothing is campaign-origin, the cleaned text is the raw text with only the repair and the banner removal applied" do
    def reconstructed_text(raw)
      repaired = Testimony::CharacterRepair.call(raw).text
      Testimony::BoilerplateRemover.call(repaired).text
    end

    it "holds on the control fixture, where the stage marks zero letters as campaign-origin" do
      bill.create_bill_llm_provisioning!(extracted_testimony: TestimonyFixtures.no_campaign_bundle)

      described_class.new(bill: bill).call
      artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

      expect(artifact["counts"]["campaign_origin_letters"]).to eq(0)
      expect(artifact["text"]).to eq(reconstructed_text(TestimonyFixtures.no_campaign_bundle))
    end

    # The campaign fixture with its campaign copies removed: run the full
    # fixture once, keep exactly ONE letter per group the stage actually
    # found, and build a new raw bundle from only those. Two letters that
    # ended up in DIFFERENT groups on the full run can never share a
    # qualifying phrase — if they did, the union-find that built those groups
    # would already have merged them into ONE component — so a re-run over
    # this residual set is guaranteed to find nothing to group, regardless of
    # which particular letters the fixture happens to carry.
    it "holds on the campaign fixture with its campaign copies removed, keeping one letter per group the full run found" do
      bill.create_bill_llm_provisioning!(extracted_testimony: TestimonyFixtures.campaign_bundle)
      described_class.new(bill: bill).call
      full_run_letters = bill.bill_llm_provisioning.reload.cleaned_testimony.fetch("letters")

      representative_positions =
        full_run_letters.group_by { |letter| letter["campaign_draft_id"] }.values.map { |members| members.first.fetch("position") }
      expect(representative_positions.length).to be >= 2 # otherwise this fixture stopped grouping and proves nothing

      raw_entries = Testimony::LetterSplitter.call(TestimonyFixtures.campaign_bundle)
      # `&:text` (Symbol#to_proc) narrows Array#values_at's own `Entry | nil` result to
      # `String`; representative_positions are always valid indices into raw_entries, so
      # `entry` is never really nil here (only Steep's signature can't see that).
      #
      # No vocabulary fixup appended here (B5): Testimony::CharacterRepair now seeds its
      # vocabulary from CITY_IT_BANNER's own spelling, so the banner's breaks resolve
      # correctly regardless of which representative letters this residual set kept.
      residual_raw = raw_entries.values_at(*representative_positions).map { |entry| entry&.text.to_s }.join

      residual_bill = create(
        :bill, sway_locale: sway_locale, legislator: bill.legislator,
        external_id: "HB9998", title: "residual"
      )
      residual_bill.create_bill_llm_provisioning!(extracted_testimony: residual_raw)
      described_class.new(bill: residual_bill).call
      artifact = residual_bill.bill_llm_provisioning.reload.cleaned_testimony

      expect(artifact["counts"]["campaign_origin_letters"]).to eq(0)
      expect(artifact["text"]).to eq(reconstructed_text(residual_raw))
    end

    # B5. Testimony::CharacterRepair only trusted a guessed letter-pair repair
    # when the correctly-spelled word appeared ELSEWHERE in the same bundle,
    # and Testimony::BoilerplateRemover then matched the city IT banner only
    # in its repaired spelling. The control fixture's LAST letter
    # is the one letter with no banner of its own, and it happens to be
    # the only place the banner's own words ("attachments", "Button") appear
    # correctly spelled — every other letter's copy of those words is broken.
    # Drop that letter and nothing in the remaining bundle corroborates the
    # guess: the banner used to survive undetected in all five remaining
    # letters, and the five identical survivors then grouped as a fake
    # "campaign" whose shared text was a security warning, not anything a
    # person wrote. CharacterRepair now seeds its vocabulary from the
    # banner's own spelling, so this holds regardless of what else survives.
    it "removes the city IT banner from every remaining letter, and forms no group from it, when the control fixture's last letter is dropped" do
      raw_entries = Testimony::LetterSplitter.call(TestimonyFixtures.no_campaign_bundle)
      residual_raw = raw_entries.first(raw_entries.length - 1).map { |entry| entry.text }.join

      residual_bill = create(
        :bill, sway_locale: sway_locale, legislator: bill.legislator,
        external_id: "HB9997", title: "residual control"
      )
      residual_bill.create_bill_llm_provisioning!(extracted_testimony: residual_raw)
      described_class.new(bill: residual_bill).call
      artifact = residual_bill.bill_llm_provisioning.reload.cleaned_testimony

      expect(artifact["counts"]["banner_occurrences"]).to eq(raw_entries.length - 1)
      expect(artifact["text"]).not_to include("This email originated from outside of")
      expect(artifact["counts"]["campaign_origin_letters"]).to eq(0)
    end

    # A third input, built here rather than read from either fixture, so the
    # invariant is proved on a bundle the two committed fixtures never
    # shaped — including one broken character, to prove the repair alone
    # (with no banner present at all) still reconstructs cleanly.
    it "holds on a third bundle, built in this spec, from letters that share no phrase" do
      raw = <<~TXT.chomp
        From: Neighbor One <one@example.com>
        Sent: Monday, January 5, 2026 9:00 AM
        To: City Council <council@example.gov>
        Subject: Testimony

        I strongly support the bicycle lane proposal on Charles Street because it will make my daily commute safer.

        ----

        From: Neighbor Two <two@example.com>
        Sent: Tuesday, January 6, 2026 10:00 AM
        To: City Council <council@example.gov>
        Subject: Testimony

        Please reject this zoning change. It would put a warehouse directly behind three elementary schools nearby.

        ----

        From: Neighbor Three <three@example.com>
        Sent: Wednesday, January 7, 2026 11:00 AM
        To: City Council <council@example.gov>
        Subject: Testimony

        My family has lived on this block for thirty years and we ask the council to fund the repaving project. Bal\u{FFFD}more needs it.
      TXT

      bill.create_bill_llm_provisioning!(extracted_testimony: raw)
      described_class.new(bill: bill).call
      artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

      expect(artifact["counts"]["campaign_origin_letters"]).to eq(0)
      expect(artifact["text"]).to eq(reconstructed_text(raw))
    end
  end

  # Measured on a real hearing bundle: the City Solicitor's letter, holding
  # every agency report in the packet, shared one eight-word window with a
  # resident's email and became the fourth "person" in a campaign of three.
  # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a public body's letter never joins a draft]]
  describe "a public body's letter and the reuse drafts" do
    it "keeps a letter the rules read as a public body out of every draft, even when it shares a template's words with the residents" do
      template = "I support Council Bill 26-0001, which will let the commission create a conservation district program for our neighborhoods."
      raw = <<~TXT.chomp
        CITY OF SPRINGFIELD

        DEPARTMENT OF LAW
        JOHN ROE, CITY SOLICITOR

        Dear President and Council Members:

        The Law Department has reviewed Council Bill 26-0001 for form and legal sufficiency. Residents wrote that #{template}

        From: Neighbor One <one@example.com>
        Sent: Monday, January 5, 2026 9:00 AM
        To: City Council <council@example.gov>
        Subject: Testimony

        #{template} My house is 125 years old.

        From: Neighbor Two <two@example.com>
        Sent: Tuesday, January 6, 2026 10:00 AM
        To: City Council <council@example.gov>
        Subject: Testimony

        #{template} We need this on my block.
      TXT

      bill.create_bill_llm_provisioning!(extracted_testimony: raw)
      described_class.new(bill: bill).call
      artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

      agency = artifact["letters"].find { |letter| letter["position"] == 0 }
      expect(agency["source_kind"]).to eq("public_body")
      expect(agency["campaign_draft_id"]).to be_nil
      expect(artifact["campaign_drafts"].pluck("letter_positions")).to eq([[1, 2]])
      expect(artifact["counts"]["public_body_letters_kept_out_of_drafts"]).to eq(1)
    end

    it "keeps an overlong (> 5 page) study segment out of campaign drafts even when it shares an eight-word phrase with residents" do
      shared_phrase = "harford road overlay district will protect neighborhood small businesses"
      study_pages = (1..6).map { |n| "Corridor study page #{n}: #{shared_phrase} according to the 2008 study." }.join("\f\n")
      raw = "#{study_pages}\f\n\n\n" \
        "From: Neighbor One <one@example.com>\nSubject: Support\n\nI believe the #{shared_phrase} for years to come.\n\n" \
        "From: Neighbor Two <two@example.com>\nSubject: Support\n\nWe know the #{shared_phrase} for years to come.\n"

      bill.create_bill_llm_provisioning!(extracted_testimony: raw)
      described_class.new(bill: bill).call
      artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

      study_letter = artifact["letters"].find { |letter| letter["position"] == 0 }
      expect(study_letter["campaign_draft_id"]).to be_nil
      expect(artifact["campaign_drafts"].pluck("letter_positions")).to eq([[1, 2]])
    end

    it "does not turn an excluded public-body or overlong letter into a singleton campaign draft even if its sender domain is a confirmed sending service" do
      SendingServiceDomain.create!(domain: "everyactioncustom.com", label: SendingServiceDomain::CONFIRMED)
      raw = <<~TXT.chomp
        From: agency@everyactioncustom.com
        Subject: Agency Report

        On behalf of the Department of Transportation, we support Bill 26-0001.

        From: resident@example.com
        Subject: Support

        Dear Council, I support Bill 26-0001.
      TXT

      bill.create_bill_llm_provisioning!(extracted_testimony: raw)
      described_class.new(bill: bill).call
      artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

      agency = artifact["letters"].find { |letter| letter["position"] == 0 }
      expect(agency["source_kind"]).to eq("public_body")
      expect(agency["campaign_draft_id"]).to be_nil
      expect(agency["campaign_origin"]).to eq(false)
      expect(agency).not_to have_key("excluded_from_drafts")
      expect(artifact["campaign_drafts"]).to be_empty
    end
  end

  describe "#call" do
    it "declares the step order — repair, banner removal, split, sender, duplicate mark, group, mark, write, classify kind, classify stance, extract entities — pinned so a later edit cannot reorder it silently" do
      expect(described_class::STEP_ORDER).to eq(%i[
        repair_characters remove_boilerplate split_into_letters read_senders
        mark_duplicate_letters group_by_reuse mark_campaign_origin write_domain_counts
        classify_source_kind classify_stance extract_organization_entities
      ])
    end

    context "with the campaign fixture" do
      before { bill.create_bill_llm_provisioning!(extracted_testimony: TestimonyFixtures.campaign_bundle) }

      it "writes a cleaned artifact with no replacement characters and no banner" do
        described_class.new(bill: bill).call
        provisioning = bill.bill_llm_provisioning.reload
        artifact = provisioning.cleaned_testimony

        expect(artifact["version"]).to eq(1)
        expect(artifact["text"]).not_to include("\u{FFFD}")
        expect(artifact["text"]).not_to include("This email originated from outside of")
        expect(provisioning.cleaned_testimony_at).to be_present
      end

      it "counts the repair and banner work, plus the raw and cleaned character totals" do
        described_class.new(bill: bill).call
        counts = bill.bill_llm_provisioning.reload.cleaned_testimony.fetch("counts")

        expect(counts["broken_words"]).to be > 0
        expect(counts["resolved_from_bundle"] + counts["resolved_by_fallback"]).to eq(counts["broken_words"])
        expect(counts["banner_occurrences"]).to be > 0
        expect(counts["raw_chars"]).to eq(TestimonyFixtures.campaign_bundle.length)
        expect(counts["cleaned_chars"]).to be < counts["raw_chars"]
      end

      it "writes one letters entry per letter marker, each carrying position, offset, length and sender" do
        described_class.new(bill: bill).call
        artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

        expect(artifact["letters"].length).to eq(42)
        expect(artifact["letters"].pluck("position")).to eq((0...42).to_a)
        expect(artifact["letters"]).to all(
          include("position", "character_offset", "characters", "sender_address", "sender_domain")
        )
        expect(artifact["letters"]).to all(satisfy { |letter| !letter.key?("text") })
      end

      it "gives an entry's character_offset as an offset into the cleaned text, not the raw column" do
        described_class.new(bill: bill).call
        artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

        first_letter = artifact["letters"].first
        expect(artifact["text"][first_letter["character_offset"], 5]).to eq("From:")
      end

      it "counts letters with a sender and distinct sender domains — measured: 42 letters, 9 domains, all with a sender" do
        described_class.new(bill: bill).call
        counts = bill.bill_llm_provisioning.reload.cleaned_testimony.fetch("counts")

        expect(counts["letter_count"]).to eq(42)
        expect(counts["letters_with_a_sender"]).to eq(42)
        expect(counts["distinct_sender_domains"]).to eq(9)
      end

      it "reads the wrapped-at-sign letter's sender as one whole address, not a bare domain" do
        described_class.new(bill: bill).call
        artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

        wrapped = artifact["letters"].find { |letter| letter["sender_address"] == TestimonyFixtures.wrapped_sender_address }
        expect(wrapped).to be_present
        expect(wrapped["sender_domain"]).to eq("everyactioncustom.com")
      end

      it "writes the same artifact when run twice on the same unchanged testimony" do
        described_class.new(bill: bill).call
        first_run = bill.bill_llm_provisioning.reload.cleaned_testimony

        described_class.new(bill: bill).call
        second_run = bill.bill_llm_provisioning.reload.cleaned_testimony

        expect(second_run).to eq(first_run)
      end

      it "collapses the main template's copies into a group and marks them campaign origin" do
        described_class.new(bill: bill).call
        artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

        expect(artifact["campaign_drafts"]).to be_present
        main_template_group = artifact["campaign_drafts"].max_by { |draft| draft["letter_positions"].length }
        expect(main_template_group["letter_positions"].length).to eq(30)
        expect(artifact["letters"]).to all(include("campaign_draft_id", "campaign_origin"))
      end

      # W-01: added_words was every letter's own words a second time, and the
      # joined text already holds them once. Measured on this fixture: the
      # stored artifact was 2.18x the cleaned text and is now 1.88x.
      it "stores each letter's body once, not a second copy alongside the joined text" do
        described_class.new(bill: bill).call
        artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

        expect(artifact["letters"]).to all(satisfy { |letter| !letter.key?("added_words") })

        # The letters index the joined text; they must not restate it. A body
        # phrase from the middle of the bundle appearing in the letter entries
        # is the second copy coming back.
        body_phrase = artifact["text"][artifact["text"].length / 2, 60]
        expect(artifact["letters"].to_json).not_to include(body_phrase)
      end

      it "counts the group work — group count, campaign-origin letters, and the added-words numbers" do
        described_class.new(bill: bill).call
        counts = bill.bill_llm_provisioning.reload.cleaned_testimony.fetch("counts")

        expect(counts["group_count"]).to be > 0
        expect(counts["campaign_origin_letters"]).to eq(42)
        expect(counts["added_words_characters"]).to be_a(Integer)
        expect(counts["senders_added_words_left_out"]).to eq(0)
      end

      it "writes one sending-service-domain-bill contribution row per distinct sender domain in this bill" do
        expect { described_class.new(bill: bill).call }
          .to change { SendingServiceDomainBill.where(bill: bill).count }.from(0).to(9)
      end

      it "sets no label on any domain the stage discovers" do
        described_class.new(bill: bill).call

        expect(SendingServiceDomain.where.not(label: SendingServiceDomain::NO_LABEL)).to be_empty
      end

      # @lat: [[testimony-letters#What a letter says about who is speaking]]
      it "writes a source_kind from the four-value list onto every letter, no gaps" do
        described_class.new(bill: bill).call
        artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

        kinds = artifact["letters"].pluck("source_kind")
        expect(kinds).to all(be_present)
        expect(kinds.uniq).to all(satisfy { |kind| Testimony::SourceKindRules::KINDS.map(&:to_s).include?(kind) })
        expect(kinds.uniq).to eq(["person_speaking_for_self"])
      end

      it "counts the source-kind work" do
        described_class.new(bill: bill).call
        counts = bill.bill_llm_provisioning.reload.cleaned_testimony.fetch("counts")

        expect(counts["person_speaking_for_self_letters"]).to eq(42)
        expect(counts["public_body_letters"]).to eq(0)
        expect(counts["named_organization_letters"]).to eq(0)
        expect(counts["person_speaking_for_org_letters"]).to eq(0)
      end

      it "writes a stance from {support, oppose, neutral} onto every letter using StanceRules in test environment" do
        described_class.new(bill: bill).call
        artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

        stances = artifact["letters"].pluck("stance")
        expect(stances).to all(be_present)
        expect(stances.uniq).to match_array(%w[support oppose neutral])
      end

      it "counts the stance work" do
        described_class.new(bill: bill).call
        counts = bill.bill_llm_provisioning.reload.cleaned_testimony.fetch("counts")

        expect(counts["stance_support_count"]).to eq(34)
        expect(counts["stance_oppose_count"]).to eq(4)
        expect(counts["stance_neutral_count"]).to eq(4)
      end

      it "uses an injected stance_classifier to classify letter stances and record counts" do
        fake_classifier = instance_double(Testimony::StanceClassifier)
        allow(fake_classifier).to receive(:call) do |text:, letters:, bill: nil|
          classified = letters.map.with_index do |letter, idx|
            letter.merge("stance" => (idx.even? ? "support" : "oppose"))
          end
          [
            classified,
            {
              "stance_support_count" => classified.count { |l| l["stance"] == "support" },
              "stance_oppose_count" => classified.count { |l| l["stance"] == "oppose" },
              "stance_neutral_count" => 0
            }
          ]
        end

        described_class.new(bill: bill, stance_classifier: fake_classifier).call
        provisioning = bill.bill_llm_provisioning.reload
        artifact = provisioning.cleaned_testimony

        expect(artifact["letters"].first["stance"]).to eq("support")
        expect(artifact["letters"].second["stance"]).to eq("oppose")
        expect(artifact["counts"]["stance_support_count"]).to eq(21)
        expect(artifact["counts"]["stance_oppose_count"]).to eq(21)
        expect(artifact["counts"]["stance_neutral_count"]).to eq(0)
      end

      it "builds default classifiers with purpose: :decision and entity extractor with purpose: :extraction" do
        allow(Testimony::SourceKindClassifier).to receive(:build).and_call_original
        allow(Testimony::StanceClassifier).to receive(:build).and_call_original
        allow(Testimony::OrganizationEntityExtractor).to receive(:build).and_call_original

        described_class.new(bill: bill).call

        expect(Testimony::SourceKindClassifier).to have_received(:build).with(purpose: :decision)
        expect(Testimony::StanceClassifier).to have_received(:build).with(purpose: :decision)
        expect(Testimony::OrganizationEntityExtractor).to have_received(:build).with(purpose: :extraction)
      end

      it "uses an injected entity_extractor to extract organization entities and record counts" do
        fake_extractor = instance_double(Testimony::OrganizationEntityExtractor)
        allow(fake_extractor).to receive(:call) do |text:, letters:|
          augmented = letters.map do |letter|
            letter.merge("extracted_org" => {"org_name" => "Civic Org", "summary" => "Supports bill"})
          end
          [
            augmented,
            {
              "org_entity_extracted_letters" => augmented.length,
              "org_entity_extraction_fallbacks" => 0
            }
          ]
        end

        described_class.new(bill: bill, entity_extractor: fake_extractor).call
        provisioning = bill.bill_llm_provisioning.reload
        artifact = provisioning.cleaned_testimony

        expect(fake_extractor).to have_received(:call) do |kwargs|
          letters = kwargs[:letters]
          expect(letters.first).to have_key("source_kind")
          expect(letters.first).to have_key("stance")
        end
        expect(artifact["letters"].first["extracted_org"]).to eq({"org_name" => "Civic Org", "summary" => "Supports bill"})
        expect(artifact["counts"]["org_entity_extracted_letters"]).to eq(42)
        expect(artifact["counts"]["org_entity_extraction_fallbacks"]).to eq(0)
      end

      it "supports .call class method forwarding kwargs to .new.call" do
        allow(described_class).to receive(:new).and_call_original
        artifact = described_class.call(bill: bill)
        expect(described_class).to have_received(:new).with(
          bill: bill,
          bill_run: nil,
          run: nil,
          classifier: nil,
          stance_classifier: nil,
          entity_extractor: nil
        )
        expect(artifact).to be_a(Hash)
        expect(artifact["version"]).to eq(described_class::ARTIFACT_VERSION)
      end
    end

    context "when extracted_testimony is blank" do
      before { bill.create_bill_llm_provisioning!(extracted_testimony: nil) }

      it "writes an artifact with empty text, an empty letters array and zero counts, and does not raise" do
        expect { described_class.new(bill: bill).call }.not_to raise_error

        artifact = bill.bill_llm_provisioning.reload.cleaned_testimony
        expect(artifact["text"]).to eq("")
        expect(artifact["letters"]).to eq([])
        expect(artifact["campaign_drafts"]).to eq([])
        expect(artifact["counts"]["broken_words"]).to eq(0)
        expect(artifact["counts"]["banner_occurrences"]).to eq(0)
        expect(artifact["counts"]["letter_count"]).to eq(0)
        expect(artifact["counts"]["letters_with_a_sender"]).to eq(0)
        expect(artifact["counts"]["distinct_sender_domains"]).to eq(0)
        expect(artifact["counts"]["group_count"]).to eq(0)
        expect(artifact["counts"]["campaign_origin_letters"]).to eq(0)
        expect(artifact["counts"]["added_words_characters"]).to eq(0)
        expect(artifact["counts"]["senders_added_words_left_out"]).to eq(0)
        expect(artifact["counts"]["person_speaking_for_self_letters"]).to eq(0)
        expect(artifact["counts"]["public_body_letters"]).to eq(0)
        expect(artifact["counts"]["named_organization_letters"]).to eq(0)
        expect(artifact["counts"]["person_speaking_for_org_letters"]).to eq(0)
        expect(artifact["counts"]["stance_support_count"]).to eq(0)
        expect(artifact["counts"]["stance_oppose_count"]).to eq(0)
        expect(artifact["counts"]["stance_neutral_count"]).to eq(0)
        expect(artifact["counts"]["org_entity_extracted_letters"]).to eq(0)
        expect(artifact["counts"]["org_entity_extraction_fallbacks"]).to eq(0)
        expect(SendingServiceDomainBill.where(bill: bill)).to be_empty
      end
    end

    # "the
    # operator's pasted testimony is NEVER cleaned" was carried as a
    # prohibition with no spec directly asserting the stage never touches
    # supplemental_testimony. Closes that gap.
    context "with both extracted_testimony and supplemental_testimony present" do
      before do
        bill.create_bill_llm_provisioning!(
          extracted_testimony: TestimonyFixtures.no_campaign_bundle,
          supplemental_testimony: "An operator's own paste, submitted verbatim, never to be cleaned."
        )
      end

      it "leaves supplemental_testimony on the row byte for byte, and never reads it into the cleaned artifact" do
        original_paste = bill.bill_llm_provisioning.supplemental_testimony

        described_class.new(bill: bill).call
        provisioning = bill.bill_llm_provisioning.reload

        expect(provisioning.supplemental_testimony).to eq(original_paste)
        artifact = provisioning.cleaned_testimony
        expect(artifact["text"]).not_to include(original_paste)
      end
    end

    # @lat: [[testimony-letters#The same letter can arrive twice]]
    context "with the same sender's same letter published at two hearings on one bill" do
      let(:two_hearing_raw) do
        <<~TXT.chomp
          From: Alice Neighbor <alice@example.com>
          Sent: Monday, September 18, 2023 9:00 AM
          To: City Council <council@example.gov>
          Subject: Testimony

          I am writing to strongly support this bill because it will improve safety in my neighborhood immediately.

          From: Bob Neighbor <bob@example.com>
          Sent: Tuesday, September 19, 2023 9:00 AM
          To: City Council <council@example.gov>
          Subject: Testimony

          Please consider the environmental impact of this proposal before any vote is taken next month.

          From: Alice Neighbor <alice@example.com>
          Sent: Monday, October 16, 2023 9:00 AM
          To: City Council <council@example.gov>
          Subject: Testimony

          I am writing to strongly support this bill because it will improve safety in my neighborhood immediately.
        TXT
      end

      before { bill.create_bill_llm_provisioning!(extracted_testimony: two_hearing_raw) }

      it "marks the second hearing's copy a repeat of the first, and marks Bob's unrelated letter as no repeat of anything" do
        described_class.new(bill: bill).call
        letters = bill.bill_llm_provisioning.reload.cleaned_testimony.fetch("letters")

        alice_first, bob, alice_second = letters
        expect(alice_first["repeat"]).to eq(false)
        expect(alice_first["repeat_of_position"]).to be_nil
        expect(bob["repeat"]).to eq(false)
        expect(alice_second["repeat"]).to eq(true)
        expect(alice_second["repeat_of_position"]).to eq(alice_first["position"])
      end

      it "counts the repeat in the artifact's counts" do
        described_class.new(bill: bill).call
        counts = bill.bill_llm_provisioning.reload.cleaned_testimony.fetch("counts")

        expect(counts["repeat_letters"]).to eq(1)
      end

      it "excludes the repeat from the group's letter_count and sender_count, the numbers an operator approves" do
        described_class.new(bill: bill).call
        artifact = bill.bill_llm_provisioning.reload.cleaned_testimony

        alice_group = artifact["campaign_drafts"].find { |draft| draft["letter_positions"].length == 2 }
        expect(alice_group).to be_present
        expect(alice_group["letter_count"]).to eq(1)
        expect(alice_group["sender_count"]).to eq(1)
        expect(alice_group["repeat_letter_count"]).to eq(1)
        # The evidence that Alice's letter arrived twice is still in the
        # artifact — only the counts an operator approves exclude it.
        expect(alice_group["letter_positions"].length).to eq(2)
      end
    end
  end

  describe "end to end: the positions prompt reads the cleaned artifact" do
    before do
      bill.create_bill_llm_provisioning!(extracted_testimony: TestimonyFixtures.campaign_bundle)
    end

    # Passes because BillPositionsPromptBuilder#testimony_sources prefers the
    # cleaned artifact.
    it "repairs the broken characters and strips the city IT banner before the positions prompt is built" do
      described_class.new(bill: bill).call

      prompt = BillPositionsPromptBuilder.new(bill).user_message

      expect(prompt).not_to include("\u{FFFD}")
      expect(prompt).not_to include("This email originated from outside of")
    end
  end
end

# B3: until the classifier's model seam became a parameter, .build returned a
# classifier with no model under Rails.env.test?, so no letter could ever
# carry :named_organization or :person_speaking_for_org through the real
# service — the product intent of this whole phase was reachable only through
# hand-built fixtures.
RSpec.describe Testimony::CleanAndGroupService do
  describe "the source-kind model pass, driven through the real service" do
    it "writes an injected model's organization verdict onto the stored artifact" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, extracted_testimony: <<~TEXT)
        From: jane@baltimorehousing.org
        I have reviewed this bill closely and my board supports it.

        Jane Doe
        Executive Director of the Baltimore Housing Coalition
      TEXT

      adapter = instance_double(Llm::LlamacppAdapter, provider_label: "llamacpp")
      allow(adapter).to receive(:generate_source_kind_classification).and_return(
        {"classifications" => [{"position" => 0, "kind" => "named_organization"}]}
      )

      described_class.new(
        bill: bill,
        classifier: Testimony::SourceKindClassifier.build(llm: adapter)
      ).call

      artifact = bill.reload.bill_llm_provisioning.cleaned_testimony
      expect(artifact["letters"].first["source_kind"]).to eq("named_organization")
      expect(artifact["counts"]["source_kind_model_fallbacks"]).to eq(0)
    end

    it "preserves manual stance overrides across subsequent CleanAndGroupService runs" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill, extracted_testimony: <<~TEXT)
        From: resident@example.com
        Dear Council,
        Here are my thoughts on the proposal.
      TEXT

      described_class.new(bill: bill).call
      artifact = provisioning.reload.cleaned_testimony
      artifact["letters"].first["stance"] = "oppose"
      artifact["letters"].first["stance_override"] = true
      provisioning.update!(cleaned_testimony: artifact)

      described_class.new(bill: bill).call
      recleaned = provisioning.reload.cleaned_testimony
      expect(recleaned["letters"].first["stance"]).to eq("oppose")
      expect(recleaned["letters"].first["stance_override"]).to eq(true)
      expect(recleaned["counts"]["stance_oppose_count"]).to eq(1)
    end

    it "disambiguates manual stance overrides by sender_address when two letters share identical body text" do
      bill = create(:bill)
      shared_body = "Dear Council, here are my thoughts on the proposal."
      raw = <<~TEXT
        From: alice@example.com
        Subject: Testimony

        #{shared_body}

        From: bob@example.com
        Subject: Testimony

        #{shared_body}
      TEXT
      provisioning = create(:bill_llm_provisioning, bill: bill, extracted_testimony: raw)

      described_class.new(bill: bill).call
      artifact = provisioning.reload.cleaned_testimony

      alice_letter = artifact["letters"].find { |l| l["sender_address"] == "alice@example.com" }
      bob_letter = artifact["letters"].find { |l| l["sender_address"] == "bob@example.com" }
      expect(alice_letter).to be_present
      expect(bob_letter).to be_present

      alice_letter["stance"] = "oppose"
      alice_letter["stance_override"] = true
      bob_letter["character_offset"] = alice_letter["character_offset"]
      bob_letter["characters"] = alice_letter["characters"]
      provisioning.update!(cleaned_testimony: artifact)

      service = described_class.new(bill: bill)
      overrides = service.send(:extract_manual_stance_overrides, provisioning.reload.cleaned_testimony)
      applied = service.send(
        :apply_manual_stance_overrides,
        artifact["text"],
        [
          alice_letter.except("stance", "stance_override"),
          bob_letter.except("stance", "stance_override")
        ]
      )

      expect(overrides.keys).to include(["alice@example.com", service.send(:letter_body_digest, artifact["text"], alice_letter)])
      expect(applied.first["stance"]).to eq("oppose")
      expect(applied.first["stance_override"]).to eq(true)
      expect(applied.second["stance_override"]).to be_nil
    end

    it "preserves excluded: true across subsequent CleanAndGroupService runs and excludes removed letters from stance counts" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill, extracted_testimony: <<~TEXT)
        From: staffer@baltimorecity.gov
        Subject: Internal Note

        Here is a brief scheduling update for the committee.

        From: resident@example.com
        Subject: Support

        Dear Council, I strongly support this bill.
      TEXT

      described_class.new(bill: bill).call
      artifact = provisioning.reload.cleaned_testimony
      first_letter = artifact["letters"].first
      first_letter["excluded"] = true
      first_letter["stance_override"] = true
      provisioning.update!(cleaned_testimony: artifact)

      described_class.new(bill: bill).call
      recleaned = provisioning.reload.cleaned_testimony
      expect(recleaned["letters"].first["excluded"]).to eq(true)
      expect(recleaned["letters"].first["stance_override"]).to eq(true)
      expect(recleaned["counts"]["stance_support_count"]).to eq(1)
      expect(recleaned["counts"]["stance_oppose_count"]).to eq(0)
      expect(recleaned["counts"]["stance_neutral_count"]).to eq(0)

      report = Testimony::CoverageReport.call(bill: bill.reload)
      expect(report.individual_letter_count).to eq(1)
    end

    it "respects an admin un-excluding a letter mid-run after CleanAndGroupService initialization" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill, extracted_testimony: <<~TEXT)
        From: resident@example.com
        Subject: Support

        Dear Council, I strongly support this bill.
      TEXT

      described_class.new(bill: bill).call
      artifact = provisioning.reload.cleaned_testimony
      artifact["letters"].first["excluded"] = true
      artifact["letters"].first["stance_override"] = true
      provisioning.update!(cleaned_testimony: artifact)

      service = described_class.new(bill: bill)
      updated_artifact = provisioning.reload.cleaned_testimony.deep_dup
      updated_artifact["letters"].first.delete("excluded")
      updated_artifact["letters"].first["stance"] = "oppose"
      updated_artifact["letters"].first["stance_override"] = true
      provisioning.update!(cleaned_testimony: updated_artifact)

      service.call
      recleaned = provisioning.reload.cleaned_testimony
      expect(recleaned["letters"].first["excluded"]).to be_nil
      expect(recleaned["letters"].first["stance"]).to eq("oppose")
      expect(recleaned["counts"]["stance_oppose_count"]).to eq(1)
    end

    it "skips excluded letters in OrganizationEntityExtractor and StanceClassifier" do
      text = "Baltimore Housing Coalition urges a favorable report on Bill 25-0064."
      letters = [
        {
          "position" => 0,
          "source_kind" => "named_organization",
          "character_offset" => 0,
          "characters" => text.length,
          "excluded" => true,
          "stance" => nil,
          "source_evidence" => {"org_name" => "Baltimore Housing Coalition"}
        }
      ]

      extracted_letters, extract_counts = Testimony::OrganizationEntityExtractor.new(enabled: false).call(text: text, letters: letters)
      expect(extracted_letters.first["extracted_org"]).to be_nil
      expect(extract_counts["org_entity_extracted_letters"]).to eq(0)

      classified_letters, stance_counts = Testimony::StanceClassifier.new(enabled: false).call(text: text, letters: letters)
      expect(classified_letters.first["stance"]).to eq("neutral")
      expect(stance_counts).to eq({
        "stance_support_count" => 0,
        "stance_oppose_count" => 0,
        "stance_neutral_count" => 0
      })
    end

    it "applies manual overrides right after read_senders so excluded letters are skipped by duplicate marking, campaign grouping, domain counts, and source-kind classification" do
      bill = create(:bill)
      shared_template = "I strongly support Council Bill 26-0099 because it protects our neighborhood transit corridors for residents."
      raw = <<~TEXT
        From: alice@everyactioncustom.com
        Subject: Support

        #{shared_template}

        From: bob@everyactioncustom.com
        Subject: Support

        #{shared_template}
      TEXT
      provisioning = create(:bill_llm_provisioning, bill: bill, extracted_testimony: raw)

      described_class.new(bill: bill).call
      artifact = provisioning.reload.cleaned_testimony
      artifact["letters"].first["excluded"] = true
      artifact["letters"].first["stance_override"] = true
      provisioning.update!(cleaned_testimony: artifact)

      described_class.new(bill: bill).call
      recleaned = provisioning.reload.cleaned_testimony

      first, second = recleaned["letters"]
      expect(first["excluded"]).to eq(true)
      expect(second["excluded"]).to be_nil
      expect(recleaned["campaign_drafts"]).to be_empty
      expect(recleaned["counts"]["person_speaking_for_self_letters"]).to eq(1)
      expect(SendingServiceDomain.find_by!(domain: "everyactioncustom.com").letter_count).to eq(1)
    end
  end
end
