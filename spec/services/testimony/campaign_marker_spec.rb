# frozen_string_literal: true

require "rails_helper"

# Marks which letters arrived through a campaign
# tool. A domain is ORIGIN, never IDENTITY or STANCE — grouping
# already happened in Testimony::CampaignDraftFinder on text alone; this
# class only decides which of those drafts (plus any lone confirmed-domain
# letter) get the campaign-origin mark, and bounds how many of the senders'
# own added words reach the model.
RSpec.describe Testimony::CampaignMarker do
  def letter(position:, domain: nil, campaign_draft_id: nil, address: nil, added_words: "", repeat: false)
    {
      "position" => position,
      "character_offset" => 0,
      "characters" => 0,
      "sender_address" => address,
      "sender_domain" => domain,
      "campaign_draft_id" => campaign_draft_id,
      "added_words" => added_words,
      "repeat" => repeat
    }
  end

  describe ".call" do
    it "marks a lone letter from a confirmed service domain, forming a draft of one whose position is read from its own words" do
      create(:sending_service_domain, :confirmed, domain: "campaign-tool.example.com")
      solo = letter(position: 0, domain: "campaign-tool.example.com", added_words: "My own words about this bill.")

      result = described_class.call(drafts: [], letters: [solo])

      expect(result.campaign_drafts.length).to eq(1)
      expect(result.campaign_drafts.first["letter_positions"]).to eq([0])
      marked = result.letters.first
      expect(marked["campaign_origin"]).to eq(true)
      expect(marked["campaign_draft_id"]).to eq(result.campaign_drafts.first["id"])
      expect(result.campaign_drafts.first["added_words"]).to eq("My own words about this bill.")
    end

    it "keeps two lone letters from one confirmed service domain as two separate drafts of one, never merged" do
      create(:sending_service_domain, :confirmed, domain: "campaign-tool.example.com")
      first = letter(position: 0, domain: "campaign-tool.example.com", added_words: "First sender's own words.")
      second = letter(position: 1, domain: "campaign-tool.example.com", added_words: "Second sender's own words.")

      result = described_class.call(drafts: [], letters: [first, second])

      expect(result.campaign_drafts.length).to eq(2)
      expect(result.campaign_drafts.pluck("letter_positions")).to contain_exactly([0], [1])
      expect(result.campaign_drafts.first["id"]).not_to eq(result.campaign_drafts.second["id"])
    end

    it "marks every letter in a reuse draft as campaign origin, regardless of any member's domain" do
      draft = {"id" => "grp1", "letter_positions" => [0, 1]}
      first = letter(position: 0, domain: "gmail.com", campaign_draft_id: "grp1")
      second = letter(position: 1, domain: "comcast.net", campaign_draft_id: "grp1")

      result = described_class.call(drafts: [draft], letters: [first, second])

      expect(result.letters.pluck("campaign_origin")).to eq([true, true])
      kept_draft = result.campaign_drafts.find { |d| d["id"] == "grp1" }
      expect(kept_draft["letter_count"]).to eq(2)
    end

    it "does not mark a letter from an ordinary mailbox domain on the strength of its domain alone" do
      solo = letter(position: 0, domain: "gmail.com", added_words: "My own opinion, shared with nobody else.")

      result = described_class.call(drafts: [], letters: [solo])

      expect(result.campaign_drafts).to eq([])
      expect(result.letters.first["campaign_origin"]).to eq(false)
      expect(result.letters.first["campaign_draft_id"]).to be_nil
    end

    it "marks nothing for a domain with no label recorded at all" do
      solo = letter(position: 0, domain: "unregistered-tool.example.com")

      result = described_class.call(drafts: [], letters: [solo])

      expect(result.campaign_drafts).to eq([])
      expect(result.letters.first["campaign_origin"]).to eq(false)
    end

    it "marks nothing for a domain explicitly labeled none" do
      create(:sending_service_domain, domain: "still-unlabeled.example.com")
      solo = letter(position: 0, domain: "still-unlabeled.example.com")

      result = described_class.call(drafts: [], letters: [solo])

      expect(result.campaign_drafts).to eq([])
      expect(result.letters.first["campaign_origin"]).to eq(false)
    end

    it "records a draft's sender count and letter count separately — two letters, one repeated sender" do
      draft = {"id" => "grp1", "letter_positions" => [0, 1]}
      first = letter(position: 0, campaign_draft_id: "grp1", address: "same@example.com")
      second = letter(position: 1, campaign_draft_id: "grp1", address: "same@example.com")

      result = described_class.call(drafts: [draft], letters: [first, second])

      kept_draft = result.campaign_drafts.first
      expect(kept_draft["letter_count"]).to eq(2)
      expect(kept_draft["sender_count"]).to eq(1)
    end

    # @lat: [[testimony-letters#The same letter can arrive twice]]
    it "excludes a repeat letter from letter_count and sender_count, while keeping it in letter_positions" do
      draft = {"id" => "grp1", "letter_positions" => [0, 1]}
      first = letter(position: 0, campaign_draft_id: "grp1", address: "same@example.com")
      second = letter(position: 1, campaign_draft_id: "grp1", address: "same@example.com", repeat: true)

      result = described_class.call(drafts: [draft], letters: [first, second])

      kept_draft = result.campaign_drafts.first
      expect(kept_draft["letter_count"]).to eq(1)
      expect(kept_draft["sender_count"]).to eq(1)
      expect(kept_draft["repeat_letter_count"]).to eq(1)
      expect(kept_draft["letter_positions"]).to eq([0, 1])
    end

    it "counts an empty-string sender address as anonymous, not as one more known sender" do
      draft = {"id" => "grp1", "letter_positions" => [0, 1, 2]}
      known = letter(position: 0, campaign_draft_id: "grp1", address: "known@example.com")
      blank_one = letter(position: 1, campaign_draft_id: "grp1", address: "")
      blank_two = letter(position: 2, campaign_draft_id: "grp1", address: "")

      result = described_class.call(drafts: [draft], letters: [known, blank_one, blank_two])

      kept_draft = result.campaign_drafts.first
      expect(kept_draft["letter_count"]).to eq(3)
      expect(kept_draft["sender_count"]).to eq(3)
    end

    it "keeps a draft's added words whole when they fit within the bound, recording zero left out" do
      stub_const("Testimony::CampaignMarker::MAX_CAMPAIGN_ADDED_CHARS", 100)
      draft = {"id" => "grp1", "letter_positions" => [0, 1]}
      first = letter(position: 0, campaign_draft_id: "grp1", added_words: "short addition one")
      second = letter(position: 1, campaign_draft_id: "grp1", added_words: "short addition two")

      result = described_class.call(drafts: [draft], letters: [first, second])

      kept_draft = result.campaign_drafts.first
      expect(kept_draft["added_words"]).to include("short addition one").and include("short addition two")
      expect(kept_draft["senders_added_words_left_out"]).to eq(0)
    end

    it "keeps senders' additions in order up to the bound, then stops and records how many were left out" do
      stub_const("Testimony::CampaignMarker::MAX_CAMPAIGN_ADDED_CHARS", 20)
      draft = {"id" => "grp1", "letter_positions" => [0, 1, 2]}
      first = letter(position: 0, campaign_draft_id: "grp1", address: "one@example.com", added_words: "fits in the bound")
      second = letter(position: 1, campaign_draft_id: "grp1", address: "two@example.com", added_words: "does not fit here")
      third = letter(position: 2, campaign_draft_id: "grp1", address: "three@example.com", added_words: "also left out")

      result = described_class.call(drafts: [draft], letters: [first, second, third])

      kept_draft = result.campaign_drafts.first
      expect(kept_draft["added_words"]).to eq("fits in the bound")
      expect(kept_draft["senders_added_words_left_out"]).to eq(2)
    end

    it "never reads a timestamp — no created_at or Time value anywhere in the class" do
      source = Rails.root.join("app", "services", "testimony", "campaign_marker.rb").read
      code_only = source.lines.reject { |line| line.strip.start_with?("#") }.join
      expect(code_only).not_to match(/created_at|Time\./i)
    end

    it "declares MAX_CAMPAIGN_ADDED_CHARS at 40,000 characters" do
      expect(described_class::MAX_CAMPAIGN_ADDED_CHARS).to eq(40_000)
    end

    it "names the domain the plurality of a draft's members share, not merely one member's" do
      draft = {"id" => "grp1", "letter_positions" => [0, 1, 2]}
      first = letter(position: 0, campaign_draft_id: "grp1", domain: "everyactioncustom.com")
      second = letter(position: 1, campaign_draft_id: "grp1", domain: "everyactioncustom.com")
      third = letter(position: 2, campaign_draft_id: "grp1", domain: "gmail.com")

      result = described_class.call(drafts: [draft], letters: [first, second, third])

      expect(result.campaign_drafts.first["dominant_domain"]).to eq("everyactioncustom.com")
    end

    it "names no domain for a draft whose members carry none" do
      draft = {"id" => "grp1", "letter_positions" => [0, 1]}
      first = letter(position: 0, campaign_draft_id: "grp1")
      second = letter(position: 1, campaign_draft_id: "grp1")

      result = described_class.call(drafts: [draft], letters: [first, second])

      expect(result.campaign_drafts.first["dominant_domain"]).to be_nil
    end

    it "skips excluded letters when building singleton drafts and finalizing draft counts" do
      create(:sending_service_domain, :confirmed, domain: "campaign-tool.example.com")
      solo_excluded = letter(position: 0, domain: "campaign-tool.example.com", added_words: "Ignored").merge("excluded" => true)

      result = described_class.call(drafts: [], letters: [solo_excluded])

      expect(result.campaign_drafts).to be_empty
      expect(result.letters.first["campaign_origin"]).to eq(false)
      expect(result.letters.first["campaign_draft_id"]).to be_nil
    end
  end
end
