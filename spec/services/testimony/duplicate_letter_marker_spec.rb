# frozen_string_literal: true

require "rails_helper"

# @lat: [[testimony-letters#The same letter can arrive twice]]
RSpec.describe Testimony::DuplicateLetterMarker do
  # Same shape spec/services/testimony/campaign_draft_finder_spec.rb builds: a
  # joined bundle plus a "letters" array of offset/length entries, the same
  # shape CleanAndGroupService threads into every STEP_ORDER step.
  def build_repeat_letters(entries)
    text = +""
    letters = []
    entries.each_with_index do |(body, address), index|
      offset = text.length
      text << body
      letters << {
        "position" => index,
        "character_offset" => offset,
        "characters" => body.length,
        "sender_address" => address,
        "sender_domain" => nil
      }
      text << "\n\n"
    end
    [text, letters]
  end

  describe ".call" do
    it "marks a second copy of the same sender's same words a repeat of the first" do
      body = "From: Alice Neighbor <alice@example.com>\nSent: Sept 18\n\nI strongly support this measure for reasons that matter to my block.\n"
      text, letters = build_repeat_letters([[body, "alice@example.com"], [body, "alice@example.com"]])

      result = described_class.call(text: text, letters: letters)

      first, second = result.letters
      expect(first["repeat"]).to eq(false)
      expect(first["repeat_of_position"]).to be_nil
      expect(second["repeat"]).to eq(true)
      expect(second["repeat_of_position"]).to eq(0)
    end

    it "never marks a letter a repeat of one arriving later in the bundle" do
      body = "From: Alice Neighbor <alice@example.com>\nSent: Sept 18\n\nI strongly support this measure for reasons that matter to my block.\n"
      text, letters = build_repeat_letters([[body, "alice@example.com"], [body, "alice@example.com"]])

      result = described_class.call(text: text, letters: letters)

      expect(result.letters.first["repeat"]).to eq(false)
    end

    it "does not mark two different senders' distinct words a repeat of each other" do
      one = "From: Alice Neighbor <alice@example.com>\nSent: Sept 18\n\nI strongly support this measure for reasons that matter to my block.\n"
      two = "From: Bob Neighbor <bob@example.com>\nSent: Sept 19\n\nI oppose this measure over the traffic study it never commissioned.\n"
      text, letters = build_repeat_letters([[one, "alice@example.com"], [two, "bob@example.com"]])

      result = described_class.call(text: text, letters: letters)

      expect(result.letters.pluck("repeat")).to eq([false, false])
    end

    it "does not mark a genuinely distinct second submission from the same sender as a repeat" do
      one = "From: Alice Neighbor <alice@example.com>\nSent: Sept 18\n\nI strongly support this measure for reasons that matter to my block.\n"
      two = "From: Alice Neighbor <alice@example.com>\nSent: Oct 16\n\nA second, separate point I want the council to hear about traffic.\n"
      text, letters = build_repeat_letters([[one, "alice@example.com"], [two, "alice@example.com"]])

      result = described_class.call(text: text, letters: letters)

      expect(result.letters.pluck("repeat")).to eq([false, false])
    end

    it "ignores the mail envelope when comparing bodies — two copies with different Sent: timestamps still match" do
      one = "From: Alice Neighbor <alice@example.com>\nSent: Monday, September 18, 2023 9:00 AM\n\nI strongly support this measure for reasons that matter to my block.\n"
      two = "From: Alice Neighbor <alice@example.com>\nSent: Monday, October 16, 2023 9:00 AM\n\nI strongly support this measure for reasons that matter to my block.\n"
      text, letters = build_repeat_letters([[one, "alice@example.com"], [two, "alice@example.com"]])

      result = described_class.call(text: text, letters: letters)

      expect(result.letters.pluck("repeat")).to eq([false, true])
    end

    it "never marks a letter with no sender address a repeat, even of an identical body" do
      body = "From: Unknown\nSent: Sept 18\n\nI strongly support this measure for reasons that matter to my block.\n"
      text, letters = build_repeat_letters([[body, nil], [body, nil]])

      result = described_class.call(text: text, letters: letters)

      expect(result.letters.pluck("repeat")).to eq([false, false])
    end

    it "never marks a blank-address, blank-body pair as duplicates of each other" do
      body = "From: Unknown\nSent: Sept 18\n\n"
      text, letters = build_repeat_letters([[body, ""], [body, ""]])

      result = described_class.call(text: text, letters: letters)

      expect(result.letters.pluck("repeat")).to eq([false, false])
    end

    it "matches case-insensitively and ignores surrounding whitespace differences in the address" do
      body = "From: Alice Neighbor <alice@example.com>\nSent: Sept 18\n\nI strongly support this measure for reasons that matter to my block.\n"
      text, letters = build_repeat_letters([[body, "Alice@Example.com"], [body, " alice@example.com "]])

      result = described_class.call(text: text, letters: letters)

      expect(result.letters.pluck("repeat")).to eq([false, true])
    end

    it "skips excluded letters so they neither become repeats nor cause subsequent active letters to be marked repeat" do
      body = "From: Alice Neighbor <alice@example.com>\nSent: Sept 18\n\nI strongly support this measure for reasons that matter to my block.\n"
      text, letters = build_repeat_letters([[body, "alice@example.com"], [body, "alice@example.com"]])
      letters.first["excluded"] = true

      result = described_class.call(text: text, letters: letters)

      expect(result.letters.pluck("repeat")).to eq([false, false])
      expect(result.letters.pluck("repeat_of_position")).to eq([nil, nil])
    end
  end
end
