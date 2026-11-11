# frozen_string_literal: true

require "rails_helper"

# @lat: [[testimony-letters#Selecting browsable constituent letters]]
RSpec.describe Testimony::BrowsableLetters, type: :service do
  let(:bill) { create(:bill) }

  def count_queries
    count = 0
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if /SCHEMA|TRANSACTION/.match?(payload[:name].to_s)

      count += 1
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscription)
    count
  end

  describe "when bill or testimony is absent" do
    it "returns an empty array and zero counts for a nil bill" do
      expect(described_class.for_bill(nil)).to eq([])
      expect(described_class.counts_for_bill(nil)).to eq({total: 0, support: 0, oppose: 0, neutral: 0})
    end

    it "returns an empty array and zero counts when bill has no provisioning" do
      bill = create(:bill)
      expect(described_class.for_bill(bill)).to eq([])
      expect(described_class.counts_for_bill(bill)).to eq({total: 0, support: 0, oppose: 0, neutral: 0})
    end

    it "returns an empty array and zero counts when cleaned_testimony is nil" do
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: nil)
      expect(described_class.for_bill(bill)).to eq([])
      expect(described_class.counts_for_bill(bill)).to eq({total: 0, support: 0, oppose: 0, neutral: 0})
    end

    it "returns an empty array and zero counts when cleaned_testimony has empty letters" do
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: {"text" => "Some text", "letters" => []})
      expect(described_class.for_bill(bill)).to eq([])
      expect(described_class.counts_for_bill(bill)).to eq({total: 0, support: 0, oppose: 0, neutral: 0})
    end

    it "returns an empty array and zero counts when cleaned_testimony has empty text" do
      letters = [{"position" => 1, "source_kind" => "person_speaking_for_self", "character_offset" => 0, "characters" => 10}]
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: {"text" => "", "letters" => letters})
      expect(described_class.for_bill(bill)).to eq([])
      expect(described_class.counts_for_bill(bill)).to eq({total: 0, support: 0, oppose: 0, neutral: 0})
    end

    it "issues zero database queries when associations are already loaded and testimony is nil" do
      prov = create(:bill_llm_provisioning, bill: bill, cleaned_testimony: nil)
      bill.bill_llm_provisioning = prov

      queries = count_queries do
        described_class.for_bill(bill)
        described_class.counts_for_bill(bill)
      end

      expect(queries).to eq(0)
    end
  end

  describe "filtering constituent letters" do
    let(:full_text) do
      "Letter 1 content\n\nLetter 2 content\n\nLetter 3 content\n\nLetter 4 content"
    end

    let(:base_letters) do
      [
        {
          "position" => 1,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 0,
          "characters" => 16,
          "stance" => "support"
        },
        {
          "position" => 2,
          "source_kind" => "named_organization",
          "character_offset" => 18,
          "characters" => 16,
          "stance" => "support"
        },
        {
          "position" => 3,
          "source_kind" => "public_body",
          "character_offset" => 36,
          "characters" => 16,
          "stance" => "oppose"
        },
        {
          "position" => 4,
          "source_kind" => "person_speaking_for_org",
          "character_offset" => 54,
          "characters" => 16,
          "stance" => "neutral"
        }
      ]
    end

    it "only includes letters with source_kind person_speaking_for_self" do
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: {
        "text" => full_text,
        "letters" => base_letters
      })

      entries = described_class.for_bill(bill)
      expect(entries.length).to eq(1)
      expect(entries.first.position).to eq(1)
      expect(entries.first.body_text).to eq("Letter 1 content")
      expect(entries.first.stance).to eq("support")
    end

    it "excludes repeat letters with repeat true or repeat_of_position set" do
      letters = [
        {
          "position" => 1,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 0,
          "characters" => 16,
          "repeat" => false,
          "repeat_of_position" => nil
        },
        {
          "position" => 2,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 18,
          "characters" => 16,
          "repeat" => true,
          "repeat_of_position" => 1
        },
        {
          "position" => 3,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 36,
          "characters" => 16,
          "repeat" => false,
          "repeat_of_position" => 1
        }
      ]

      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: {
        "text" => full_text,
        "letters" => letters
      })

      entries = described_class.for_bill(bill)
      expect(entries.map(&:position)).to eq([1])
    end

    it "excludes segments exceeding the five-page constituent ceiling" do
      short_letter = "I support this bill for our neighborhood."
      six_page_study = (1..6).map { |n| "Study page #{n} text with full sentences." }.join("\f\n")
      combined_text = "#{short_letter}\n\n#{six_page_study}"
      letters = [
        {
          "position" => 0,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 0,
          "characters" => short_letter.length,
          "stance" => "support"
        },
        {
          "position" => 1,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => short_letter.length + 2,
          "characters" => six_page_study.length,
          "stance" => "neutral"
        }
      ]

      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: {
        "text" => combined_text,
        "letters" => letters
      })

      entries = described_class.for_bill(bill)
      expect(entries.map(&:position)).to eq([0])
    end
  end

  describe "envelope stripping, privacy, and non-blank body requirements" do
    let(:text_with_envelope) do
      "From: Jane Doe <jane@example.com>\n" \
        "Sent: Monday, October 15, 2026 10:00 AM\n" \
        "To: Council <council@baltimorecity.gov>\n" \
        "Subject: In support of the bill\n\n" \
        "I strongly support this bill for Baltimore families.\n\n" \
        "From: Empty Letter <empty@example.com>\n" \
        "Sent: Tuesday, October 16, 2026 11:00 AM\n" \
        "Subject: Blank Body\n\n"
    end

    let(:letters) do
      first_len = "From: Jane Doe <jane@example.com>\nSent: Monday, October 15, 2026 10:00 AM\nTo: Council <council@baltimorecity.gov>\nSubject: In support of the bill\n\nI strongly support this bill for Baltimore families.".length
      second_len = "From: Empty Letter <empty@example.com>\nSent: Tuesday, October 16, 2026 11:00 AM\nSubject: Blank Body\n\n".length

      [
        {
          "position" => 1,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 0,
          "characters" => first_len,
          "stance" => "support"
        },
        {
          "position" => 2,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => first_len + 2,
          "characters" => second_len,
          "stance" => "neutral"
        }
      ]
    end

    it "strips envelope headers and excludes letters whose body text is blank" do
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: {
        "text" => text_with_envelope,
        "letters" => letters
      })

      entries = described_class.for_bill(bill)
      expect(entries.length).to eq(1)
      expect(entries.first.position).to eq(1)
      expect(entries.first.body_text).to eq("I strongly support this bill for Baltimore families.")
    end

    it "skips letters with nil character_offset or nil position without slicing from offset 0" do
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: {
        "text" => "Valid letter body text",
        "letters" => [
          {
            "position" => nil,
            "source_kind" => "person_speaking_for_self",
            "character_offset" => 0,
            "characters" => 22,
            "stance" => "support"
          },
          {
            "position" => 1,
            "source_kind" => "person_speaking_for_self",
            "character_offset" => nil,
            "characters" => 22,
            "stance" => "support"
          }
        ]
      })

      expect(described_class.for_bill(bill)).to eq([])
    end

    it "ensures Entry does not expose sender_address or sender_domain" do
      entry = described_class::Entry.new(
        position: 1,
        label: "Constituent Letter #1",
        stance: "support",
        body_text: "Clean text"
      )
      expect(entry).not_to respond_to(:sender_address)
      expect(entry).not_to respond_to(:sender_domain)
    end
  end

  describe "sequential labeling in ascending position order" do
    let(:full_text) do
      "Letter at pos 5\n\nLetter at pos 2\n\nLetter at pos 9"
    end

    let(:unordered_letters) do
      [
        {
          "position" => 5,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 0,
          "characters" => 15,
          "stance" => "support"
        },
        {
          "position" => 2,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 17,
          "characters" => 15,
          "stance" => "oppose"
        },
        {
          "position" => 9,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 34,
          "characters" => 15,
          "stance" => "neutral"
        }
      ]
    end

    it "orders entries by position and assigns sequential 1-based labels" do
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: {
        "text" => full_text,
        "letters" => unordered_letters
      })

      entries = described_class.for_bill(bill)
      expect(entries.map(&:position)).to eq([2, 5, 9])
      expect(entries.map(&:label)).to eq([
        "Constituent Letter #1",
        "Constituent Letter #2",
        "Constituent Letter #3"
      ])
    end
  end

  describe "stance normalization" do
    let(:full_text) { "Letter 1\n\nLetter 2\n\nLetter 3\n\nLetter 4" }

    let(:letters) do
      [
        {"position" => 1, "source_kind" => "person_speaking_for_self", "character_offset" => 0, "characters" => 8, "stance" => "support"},
        {"position" => 2, "source_kind" => "person_speaking_for_self", "character_offset" => 10, "characters" => 8, "stance" => "oppose"},
        {"position" => 3, "source_kind" => "person_speaking_for_self", "character_offset" => 20, "characters" => 8, "stance" => nil},
        {"position" => 4, "source_kind" => "person_speaking_for_self", "character_offset" => 30, "characters" => 8, "stance" => "unknown_value"}
      ]
    end

    it "preserves valid stances and normalizes missing or unknown stances to neutral" do
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: {
        "text" => full_text,
        "letters" => letters
      })

      entries = described_class.for_bill(bill)
      expect(entries.map(&:stance)).to eq(%w[support oppose neutral neutral])
    end
  end

  describe "counts_for_bill and counts_from_entries" do
    let(:entries) do
      [
        described_class::Entry.new(position: 1, label: "Constituent Letter #1", stance: "support", body_text: "Text 1"),
        described_class::Entry.new(position: 2, label: "Constituent Letter #2", stance: "support", body_text: "Text 2"),
        described_class::Entry.new(position: 3, label: "Constituent Letter #3", stance: "oppose", body_text: "Text 3"),
        described_class::Entry.new(position: 4, label: "Constituent Letter #4", stance: "neutral", body_text: "Text 4")
      ]
    end

    it "computes accurate total and stance breakdown from entries" do
      counts = described_class.counts_from_entries(entries)
      expect(counts).to eq({
        total: 4,
        support: 2,
        oppose: 1,
        neutral: 1
      })
    end

    it "computes counts_for_bill matching the entries" do
      full_text = "Text 1\n\nText 2\n\nText 3\n\nText 4"
      letters = [
        {"position" => 1, "source_kind" => "person_speaking_for_self", "character_offset" => 0, "characters" => 6, "stance" => "support"},
        {"position" => 2, "source_kind" => "person_speaking_for_self", "character_offset" => 8, "characters" => 6, "stance" => "support"},
        {"position" => 3, "source_kind" => "person_speaking_for_self", "character_offset" => 16, "characters" => 6, "stance" => "oppose"},
        {"position" => 4, "source_kind" => "person_speaking_for_self", "character_offset" => 24, "characters" => 6, "stance" => "neutral"}
      ]
      create(:bill_llm_provisioning, bill: bill, cleaned_testimony: {
        "text" => full_text,
        "letters" => letters
      })

      counts = described_class.counts_for_bill(bill)
      expect(counts).to eq({
        total: 4,
        support: 2,
        oppose: 1,
        neutral: 1
      })
    end
  end

  describe "campaign draft filtering and database query budget" do
    let(:full_text) do
      "Constituent independent letter\n\n" \
        "Campaign draft letter 1\n\n" \
        "Campaign draft letter 2\n\n" \
        "Rejected campaign draft letter"
    end

    let(:letters) do
      [
        {
          "position" => 1,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 0,
          "characters" => 30,
          "campaign_origin" => false,
          "stance" => "support"
        },
        {
          "position" => 2,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 32,
          "characters" => 23,
          "campaign_origin" => true,
          "campaign_draft_id" => "draft-individual-1",
          "stance" => "support"
        },
        {
          "position" => 3,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 57,
          "characters" => 23,
          "campaign_origin" => true,
          "campaign_draft_id" => "draft-approved-1",
          "stance" => "oppose"
        },
        {
          "position" => 4,
          "source_kind" => "person_speaking_for_self",
          "character_offset" => 82,
          "characters" => 30,
          "campaign_origin" => true,
          "campaign_draft_id" => "draft-rejected-1",
          "stance" => "neutral"
        }
      ]
    end

    let(:campaign_drafts) do
      [
        {"id" => "draft-individual-1", "letter_positions" => [2]},
        {"id" => "draft-approved-1", "letter_positions" => [3]},
        {"id" => "draft-rejected-1", "letter_positions" => [4]}
      ]
    end

    context "when individual_campaign_draft_hash_list is empty" do
      it "excludes all campaign_origin letters and issues zero SQL queries to campaigns" do
        prov = create(
          :bill_llm_provisioning,
          bill: bill,
          cleaned_testimony: {
            "text" => full_text,
            "letters" => letters,
            "campaign_drafts" => campaign_drafts
          },
          individual_campaign_draft_hashes: []
        )
        bill.bill_llm_provisioning = prov

        queries = count_queries do
          entries = described_class.for_bill(bill)
          expect(entries.map(&:position)).to eq([1])
        end

        expect(queries).to eq(0)
      end
    end

    context "when individual_campaign_draft_hash_list is present" do
      let!(:prov) do
        create(
          :bill_llm_provisioning,
          bill: bill,
          cleaned_testimony: {
            "text" => full_text,
            "letters" => letters,
            "campaign_drafts" => campaign_drafts
          },
          individual_campaign_draft_hashes: ["draft-individual-1", "draft-approved-1", "draft-rejected-1"],
          rejected_campaign_draft_hashes: ["draft-rejected-1"]
        )
      end

      before do
        create(
          :campaign,
          bill: bill,
          source_campaign_draft_hash: "draft-approved-1",
          name: "Approved Campaign",
          support: "AGAINST",
          summary: "Approved opposition campaign"
        )
      end

      it "includes letters marked individual, while excluding rejected drafts and approved campaigns" do
        entries = described_class.for_bill(bill.reload)

        expect(entries.map(&:position)).to eq([1, 2])
        expect(entries.map(&:label)).to eq(["Constituent Letter #1", "Constituent Letter #2"])
      end

      it "issues exactly one query against bill.campaigns when campaigns are not loaded" do
        reloaded_bill = Bill.find(bill.id)
        queries = count_queries do
          described_class.for_bill(reloaded_bill)
        end

        expect(queries).to be <= 2
      end
    end

    it "returns empty array when cleaned_testimony_at is older than testimony_fetched_at" do
      create(
        :bill_llm_provisioning,
        bill: bill,
        cleaned_testimony_at: 2.hours.ago,
        testimony_fetched_at: 1.hour.ago,
        cleaned_testimony: {
          "text" => "I support this bill.",
          "letters" => [
            {
              "position" => 1,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => 0,
              "characters" => 20,
              "stance" => "support"
            }
          ]
        }
      )

      expect(described_class.for_bill(bill.reload)).to eq([])
    end

    it "strips leading blank lines, forwarded dividers, recipient headers, and sender_address from body_text" do
      text = "\n-----Original Message-----\nFrom: resident@example.org\nSent: Monday\nTo: council@baltimorecity.gov\n\nI support this bill. Contact me at resident@example.org"
      create(
        :bill_llm_provisioning,
        bill: bill,
        cleaned_testimony: {
          "text" => text,
          "letters" => [
            {
              "position" => 1,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => 0,
              "characters" => text.length,
              "sender_address" => "resident@example.org",
              "stance" => "support"
            }
          ]
        }
      )

      entries = described_class.for_bill(bill.reload)
      expect(entries.length).to eq(1)
      expect(entries.first.body_text).to eq("I support this bill. Contact me at")
      expect(entries.first.body_text).not_to include("resident@example.org")
      expect(entries.first.body_text).not_to include("Original Message")
    end

    it "strips trailing print-header stub pages from browsable letter bodies and skips standalone print-header stubs with or without a leading page number" do
      stub_entry = "Leva, Anthony F. (City Council)\n"
      letter_with_trailing_stub = "From: jane@example.com\nSubject: Support\n\nDear Council,\nI support this bill.\f\n2\nLeva, Anthony F. (City Council)\n"
      full_text = "#{stub_entry}\n#{letter_with_trailing_stub}"

      create(
        :bill_llm_provisioning,
        bill: bill,
        cleaned_testimony: {
          "text" => full_text,
          "letters" => [
            {
              "position" => 0,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => 0,
              "characters" => stub_entry.length,
              "sender_address" => nil,
              "stance" => "neutral"
            },
            {
              "position" => 1,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => stub_entry.length + 1,
              "characters" => letter_with_trailing_stub.length,
              "sender_address" => "jane@example.com",
              "stance" => "support"
            }
          ]
        }
      )

      entries = described_class.for_bill(bill.reload)
      expect(entries.length).to eq(1)
      expect(entries.first.position).to eq(1)
      expect(entries.first.body_text).to eq("Dear Council,\nI support this bill.")
      expect(entries.first.body_text).not_to include("Leva, Anthony")
    end

    it "unwraps ragged PDF-wrapped prose lines while keeping salutations, lists, and sign-offs intact" do
      letter_text = "Mayor Scott- and Coucilman \n" \
        "I live along side of the proposed Overlay Bill. Our District Coucilman Mr Dorsey-has written a Bill that \n" \
        "is going \n" \
        "to affect my community, Lauraville. Going up the first block 500' from Harford Road. Thats estimating \n" \
        "5 houses on BOTH sides \n" \
        "a total of 10. Lauraville isn't a large community. Its small and retains its family orientated community. "

      create(
        :bill_llm_provisioning,
        bill: bill,
        cleaned_testimony: {
          "text" => letter_text,
          "letters" => [
            {
              "position" => 0,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => 0,
              "characters" => letter_text.length,
              "sender_address" => "resident@example.com",
              "stance" => "oppose"
            }
          ]
        }
      )

      entries = described_class.for_bill(bill.reload)
      expect(entries.length).to eq(1)
      expect(entries.first.body_text).to eq(
        "Mayor Scott- and Coucilman\n" \
        "I live along side of the proposed Overlay Bill. Our District Coucilman Mr Dorsey-has written a Bill that " \
        "is going to affect my community, Lauraville. Going up the first block 500' from Harford Road. Thats estimating " \
        "5 houses on BOTH sides a total of 10. Lauraville isn't a large community. Its small and retains its family orientated community."
      )
    end

    it "excludes letters marked excluded: true" do
      full_text = "First constituent letter.\n\nSecond constituent letter."
      create(
        :bill_llm_provisioning,
        bill: bill,
        cleaned_testimony: {
          "text" => full_text,
          "letters" => [
            {
              "position" => 0,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => 0,
              "characters" => 25,
              "excluded" => true,
              "stance" => "support"
            },
            {
              "position" => 1,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => 27,
              "characters" => 26,
              "stance" => "oppose"
            }
          ]
        }
      )

      entries = described_class.for_bill(bill.reload)
      expect(entries.map(&:position)).to eq([1])
      expect(described_class.counts_for_bill(bill)).to eq({total: 1, support: 0, oppose: 1, neutral: 0})
    end

    it "excludes internal staff routing notes and administrative government correspondence while keeping city employees writing as residents" do
      routing_note = "From: staffer@baltimorecity.gov\nSubject: Bill 25-0169\n\nGood morning, please add to the bill file."
      admin_note = "From: reviewer@baltimorecity.gov\nSubject: Bill 25-0169\n\nWe reviewed this for the hearing record and have no objection to the passage."
      resident_gov = "From: jane.doe@baltimorecity.gov\nSubject: Bill 25-0169\n\nI am writing as a resident of this block, not for my employer, to ask you to pass this bill for the hearing record."
      full_text = "#{routing_note}\n\n#{admin_note}\n\n#{resident_gov}"

      create(
        :bill_llm_provisioning,
        bill: bill,
        cleaned_testimony: {
          "text" => full_text,
          "letters" => [
            {
              "position" => 0,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => 0,
              "characters" => routing_note.length,
              "sender_address" => "staffer@baltimorecity.gov",
              "sender_domain" => "baltimorecity.gov",
              "stance" => "neutral"
            },
            {
              "position" => 1,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => routing_note.length + 2,
              "characters" => admin_note.length,
              "sender_address" => "reviewer@baltimorecity.gov",
              "sender_domain" => "baltimorecity.gov",
              "stance" => "neutral"
            },
            {
              "position" => 2,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => routing_note.length + 2 + admin_note.length + 2,
              "characters" => resident_gov.length,
              "sender_address" => "jane.doe@baltimorecity.gov",
              "sender_domain" => "baltimorecity.gov",
              "stance" => "support"
            }
          ]
        }
      )

      entries = described_class.for_bill(bill.reload)
      expect(entries.map(&:position)).to eq([2])
    end

    it "preserves constituent narrative letters that mention 'for the hearing record' or 'please see below'" do
      narrative_letter = "From: neighbor@example.com\nSubject: Bill 25-0169\n\nThis zoning change will worsen traffic on Harford Road and hurt our neighborhood schools. Please include my comments for the hearing record."

      create(
        :bill_llm_provisioning,
        bill: bill,
        cleaned_testimony: {
          "text" => narrative_letter,
          "letters" => [
            {
              "position" => 0,
              "source_kind" => "person_speaking_for_self",
              "character_offset" => 0,
              "characters" => narrative_letter.length,
              "sender_address" => "neighbor@example.com",
              "sender_domain" => "example.com",
              "stance" => "oppose"
            }
          ]
        }
      )

      entries = described_class.for_bill(bill.reload)
      expect(entries.length).to eq(1)
      expect(entries.first.body_text).to include("This zoning change will worsen traffic on Harford Road")
    end
  end
end
