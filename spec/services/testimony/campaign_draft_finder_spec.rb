# frozen_string_literal: true

require "rails_helper"
require "support/testimony_fixtures"

# Groups letters by the text they reuse, at phrase
# grain, plus SHINGLE_WINDOW_WORDS-word sliding-window shingles.
# Runs on already-repaired, already-banner-stripped text
# (CleanAndGroupService::STEP_ORDER) — grouping is decided by reused text
# alone, never by domain.
RSpec.describe Testimony::CampaignDraftFinder do
  # Builds a Testimony::LetterSplitter::Entry-shaped letters array (the
  # artifact's "letters" hashes) by concatenating whole letter bodies and
  # reading each one's own offset/length back out of the joined text — the
  # same shape CleanAndGroupService threads into every STEP_ORDER step.
  def build_letters(bodies)
    text = +""
    letters = []
    bodies.each_with_index do |body, index|
      offset = text.length
      text << body
      letters << {
        "position" => index,
        "character_offset" => offset,
        "characters" => body.length,
        "sender_address" => nil,
        "sender_domain" => nil
      }
      text << "\n\n"
    end
    [text, letters]
  end

  describe ".call" do
    it "produces zero drafts for a bundle holding exactly one letter" do
      text, letters = build_letters(["From: Jane Doe <jane@example.com>\nDear Council,\n\nI support this measure for reasons of my own that run on for a while.\n"])

      result = described_class.call(text: text, letters: letters)

      expect(result.campaign_drafts).to eq([])
      expect(result.letters.pluck("campaign_draft_id")).to eq([nil])
    end

    it "produces zero drafts when several letters share no phrase" do
      text, letters = build_letters([
        "From: Jane Doe <jane@example.com>\nDear Council,\n\nI support this measure for reasons that are entirely my own to explain.\n",
        "From: John Roe <john@example.com>\nDear Council,\n\nI oppose this measure because of concerns nobody else in this bundle raises.\n"
      ])

      result = described_class.call(text: text, letters: letters)

      expect(result.campaign_drafts).to eq([])
      expect(result.letters.pluck("campaign_draft_id")).to eq([nil, nil])
    end

    it "passes through a letter holding a single paragraph and a letter holding none, without raising, neither in a draft" do
      text, letters = build_letters([
        "From: Jane Doe <jane@example.com>\nDear Council,\n\nOne paragraph and nothing shared with anybody else in this bundle at all.\n",
        "From: John Roe <john@example.com>\n"
      ])

      expect { described_class.call(text: text, letters: letters) }.not_to raise_error

      result = described_class.call(text: text, letters: letters)
      expect(result.campaign_drafts).to eq([])
    end

    it "groups the campaign template's copies, one draft holding every copy" do
      one_letter = "From: Jane Doe <jane@example.com>\n" \
        "Sent: Monday, June 2, 2026 2:01 PM\n" \
        "To: City Council <citycouncil@example.gov>\n" \
        "Subject: Support for Bill 1\n\n" \
        "Dear Council Members,\n\n" \
        "I am writing today to urge you to support this bill, an ordinance that\n" \
        "would improve the transportation system for every resident of this city.\n\n" \
        "Thank you,\nJane Doe\n"
      bodies = 3.times.map { |i| one_letter.sub("Jane Doe", "Sender #{i}").sub("jane@example.com", "sender#{i}@example.com") }
      text, letters = build_letters(bodies)

      result = described_class.call(text: text, letters: letters)

      expect(result.campaign_drafts.length).to eq(1)
      expect(result.campaign_drafts.first["letter_positions"]).to eq([0, 1, 2])
      expect(result.letters.pluck("campaign_draft_id")).to eq([result.campaign_drafts.first["id"]] * 3)
    end

    it "counts accented letters toward MIN_PHRASE_CHARS, so a shared non-English line still groups" do
      # 28 Unicode letters but only 16 ASCII a-zA-Z letters — long enough under
      # a Unicode-aware count, too short under an ASCII-only one.
      accented_line = "Estámós áquí párá ápóyár éstá léy"
      bodies = [
        "From: Ana Ruiz <ana@example.com>\nDear Council,\n\n#{accented_line}\n",
        "From: Luis Vega <luis@example.com>\nDear Council,\n\n#{accented_line}\n"
      ]
      text, letters = build_letters(bodies)

      result = described_class.call(text: text, letters: letters)

      expect(result.campaign_drafts.length).to eq(1)
      expect(result.campaign_drafts.first["letter_positions"]).to eq([0, 1])
    end

    it "joins a letter that keeps some of the template's paragraphs and rewrites others, on the paragraphs it kept" do
      template_paragraph = "I am writing today to urge you to support this bill, an ordinance that\n" \
        "would improve the transportation system for every resident of this city."
      own_paragraph = "I also want to add that the crosswalk near my block has needed repair for a very long time now."

      letter_one = "From: Jane Doe <jane@example.com>\nDear Council,\n\n#{template_paragraph}\n"
      letter_two = "From: John Roe <john@example.com>\nDear Council,\n\n#{template_paragraph}\n"
      letter_three = "From: Amy Poe <amy@example.com>\nDear Council,\n\n#{template_paragraph}\n\n#{own_paragraph}\n"

      text, letters = build_letters([letter_one, letter_two, letter_three])

      result = described_class.call(text: text, letters: letters)

      expect(result.campaign_drafts.length).to eq(1)
      third_letter = result.letters.last
      expect(third_letter["campaign_draft_id"]).to eq(result.campaign_drafts.first["id"])
      expect(third_letter["added_words"]).to include("crosswalk near my block")
      expect(third_letter["added_words"]).not_to include("urge you to support this bill")
    end

    it "never lets a candidate phrase span a line break — a phrase that would cross one is cut at the break, not joined across it" do
      # Exactly 7 words in each letter, under SHINGLE_WINDOW_WORDS (8), so
      # shingling contributes nothing here — this isolates the line matcher.
      wrapped = "From: Jane Doe <jane@example.com>\nDear Council,\n\n" \
        "Transportation infrastructure funding\n" \
        "requires community support today\n"
      joined = "From: John Roe <john@example.com>\nDear Council,\n\n" \
        "Transportation infrastructure funding requires community support today\n"

      text, letters = build_letters([wrapped, joined])

      result = described_class.call(text: text, letters: letters)

      # If a phrase were allowed to join across the break, these two letters
      # would match (the joined letter's one line equals the wrapped letter's
      # two lines concatenated with a space) and form a draft. They must not.
      expect(result.campaign_drafts).to eq([])
    end

    # @lat: [[testimony-letters#The splitter is biased toward leaving letters joined]]
    context "when the mail envelope is not one clean block" do
      it "does not connect two unrelated letters through a shared recipient line, even when a blank line sits inside the envelope" do
        letter_one = "From: Jane Doe <jane@example.com>\nSent: Monday\n\n" \
          "To: City Council <citycouncil@example.gov>\nSubject: Support for Bill 1\n\n" \
          "Dear Council,\n\nI support this measure for reasons that are entirely my own to explain here.\n"
        letter_two = "From: John Roe <john@example.com>\nSent: Tuesday\n\n" \
          "To: City Council <citycouncil@example.gov>\nSubject: Oppose Bill 1\n\n" \
          "Dear Council,\n\nI oppose this measure because of concerns nobody else in this bundle raises.\n"

        text, letters = build_letters([letter_one, letter_two])

        result = described_class.call(text: text, letters: letters)

        expect(result.campaign_drafts).to eq([])
        expect(result.letters.pluck("campaign_draft_id")).to eq([nil, nil])
      end

      it "keeps a letter's own opening paragraph when no blank line separates it from Subject:, so it still groups with a real copy" do
        opening = "I am writing today to urge you to support this bill, an ordinance that helps every resident."
        letter_one = "From: Jane Doe <jane@example.com>\nSubject: Support for Bill 1\n#{opening}\n"
        letter_two = "From: John Roe <john@example.com>\nSubject: Support for Bill 1\n\n#{opening}\n"

        text, letters = build_letters([letter_one, letter_two])

        result = described_class.call(text: text, letters: letters)

        expect(result.campaign_drafts.length).to eq(1)
        expect(result.campaign_drafts.first["letter_positions"]).to eq([0, 1])
      end
    end

    it "does not group two letters that share only the city IT banner, because the banner is removed before anything is compared" do
      banner = Testimony::BoilerplateRemover::CITY_IT_BANNER
      letter_one = "From: Jane Doe <jane@example.com>\n\n#{banner}\n\nDear Council,\n\nI support this measure for my own reasons entirely unrelated to the other letter.\n"
      letter_two = "From: John Roe <john@example.com>\n\n#{banner}\n\nDear Council,\n\nI oppose this measure for reasons of my own that share nothing with the first letter.\n"

      stripped_one = Testimony::BoilerplateRemover.call(letter_one).text
      stripped_two = Testimony::BoilerplateRemover.call(letter_two).text
      text, letters = build_letters([stripped_one, stripped_two])

      result = described_class.call(text: text, letters: letters)

      expect(result.campaign_drafts).to eq([])
    end

    it "gives the same bundle the same draft identity twice running" do
      one_letter = "From: Jane Doe <jane@example.com>\nDear Council,\n\n" \
        "I am writing today to urge you to support this bill, an ordinance that helps everyone.\n"
      bodies = 2.times.map { |i| one_letter.sub("Jane Doe", "Sender #{i}") }
      text, letters = build_letters(bodies)

      first_run = described_class.call(text: text, letters: letters)
      second_run = described_class.call(text: text, letters: letters)

      expect(first_run.campaign_drafts.first["id"]).to eq(second_run.campaign_drafts.first["id"])
    end

    it "never reads a timestamp — no created_at, updated_at or Time value anywhere in the class" do
      source = Rails.root.join("app", "services", "testimony", "campaign_draft_finder.rb").read
      code_only = source.lines.reject { |line| line.strip.start_with?("#") }.join
      expect(code_only).not_to match(/created_at|updated_at|Time\.|\.hours|\.days/i)
    end

    context "shingle matching" do
      it "merges two letters whose shared sentence wraps at a different column in each, even though no physical line is identical" do
        letter_one = "From: Jane Doe <jane@example.com>\nDear Council,\n\n" \
          "I am writing in support of Baltimore City Council bills because they will\n" \
          "help every resident of this city travel safely to work and back home again.\n"
        letter_two = "From: John Roe <john@example.com>\nDear Council,\n\n" \
          "I am writing in support of Baltimore City Council bills because\n" \
          "they will help every resident of this city travel safely to work and\n" \
          "back home again.\n"

        text, letters = build_letters([letter_one, letter_two])

        result = described_class.call(text: text, letters: letters)

        expect(result.campaign_drafts.length).to eq(1)
        expect(result.campaign_drafts.first["letter_positions"]).to eq([0, 1])
        expect(result.letters.pluck("campaign_draft_id")).to eq([result.campaign_drafts.first["id"]] * 2)
      end

      it "does not merge two unrelated letters that happen to share a short phrase under SHINGLE_WINDOW_WORDS words" do
        letter_one = "From: Jane Doe <jane@example.com>\nDear Council,\n\n" \
          "Thank you for reading this.\n\n" \
          "I support this measure because it repairs sidewalks near my home.\n"
        letter_two = "From: John Roe <john@example.com>\nDear Council,\n\n" \
          "Thank you for reading this.\n\n" \
          "I oppose this measure because it raises costs for small landlords.\n"

        text, letters = build_letters([letter_one, letter_two])

        result = described_class.call(text: text, letters: letters)

        expect(result.campaign_drafts).to eq([])
        expect(result.letters.pluck("campaign_draft_id")).to eq([nil, nil])
      end

      it "skips shingling a paragraph with fewer than SHINGLE_WINDOW_WORDS words" do
        letter_one = "From: Jane Doe <jane@example.com>\nDear Council,\n\nShort note in support.\n"
        letter_two = "From: John Roe <john@example.com>\nDear Council,\n\nShort note in support.\n"

        text, letters = build_letters([letter_one, letter_two])

        result = described_class.call(text: text, letters: letters)

        expect(result.campaign_drafts).to eq([])
      end
    end

    context "with the real campaign fixture, run through the full clean-and-split pipeline" do
      # Measured with `grep -c "everyactioncustom.com" spec/fixtures/testimony/campaign_bundle.txt`
      # — hard-coded rather than re-derived so a fixture edit that silently
      # drops a copy is caught here instead of passing for the wrong reason.
      it "collapses the main template's copies into one draft holding every copy planted in the fixture" do
        repaired = Testimony::CharacterRepair.call(TestimonyFixtures.campaign_bundle).text
        stripped = Testimony::BoilerplateRemover.call(repaired).text
        entries = Testimony::LetterSplitter.call(stripped)
        letters = entries.map do |entry|
          sender = Testimony::SenderReader.call(entry.text)
          {
            "position" => entry.position,
            "character_offset" => entry.character_offset,
            "characters" => entry.text.length,
            "sender_address" => sender.address,
            "sender_domain" => sender.domain
          }
        end

        result = described_class.call(text: stripped, letters: letters)

        main_template_draft = result.campaign_drafts.max_by { |draft| draft["letter_positions"].length }
        expect(main_template_draft["letter_positions"].length).to eq(30)
      end
    end
  end
end
