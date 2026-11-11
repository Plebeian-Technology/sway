# == Schema Information
#
# Table name: bill_llm_provisionings
# Database name: primary
#
#  id                               :integer          not null, primary key
#  categories_unmatched_at          :datetime
#  citations_valid                  :boolean
#  cleaned_testimony                :text
#  cleaned_testimony_at             :datetime
#  diff_content                     :text
#  diff_generated_at                :datetime
#  draft_org_positions              :text
#  extracted_testimony              :text
#  generation_error                 :text
#  generation_status                :string
#  hearings_fetched_at              :datetime
#  individual_campaign_draft_hashes :text
#  invalid_citations                :text
#  invalid_news_urls                :text
#  llm_full_breakdown               :text
#  llm_generated_at                 :datetime
#  llm_model                        :string
#  llm_provider                     :string
#  llm_summary                      :text
#  news_articles                    :text
#  news_articles_fetched_at         :datetime
#  news_urls_valid                  :boolean
#  rejected_campaign_draft_hashes   :text
#  summary_batch_expires_at         :datetime
#  summary_batch_testimony_digest   :string
#  supplemental_testimony           :text
#  testimony_attachments            :text
#  testimony_fetched_at             :datetime
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  bill_id                          :integer          not null
#  summary_batch_id                 :string
#  summary_run_id                   :string
#
# Indexes
#
#  index_bill_llm_provisionings_on_bill_id                  (bill_id) UNIQUE
#  index_bill_llm_provisionings_on_categories_unmatched_at  (categories_unmatched_at) WHERE categories_unmatched_at IS NOT NULL
#  index_bill_llm_provisionings_on_llm_generated_at         (llm_generated_at)
#  index_bill_llm_provisionings_on_summary_batch_id         (summary_batch_id)
#  index_bill_llm_provisionings_on_summary_run_id           (summary_run_id) UNIQUE WHERE summary_run_id IS NOT NULL
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
FactoryBot.define do
  factory :bill_llm_provisioning do
    bill

    # @lat: [[bill-llm-provisioning-factory-design#:with_diff_content does not mean "there is source text to summarize"]]
    trait :with_diff_content do
      diff_content { "# Test diff" }
      diff_generated_at { Time.zone.now }
    end

    # @lat: [[bill-llm-provisioning-factory-design#:with_testimony and why :with_drafts pulls it in automatically]]
    trait :with_testimony do
      # Zero keeps the gate closed, which is what every existing caller of this
      # trait wants. A positive value pads the bundle that far past the prompt's
      # budget, so a spec that means to test the gate OPENING can ask for a real
      # cut instead of hand-building an artifact (W-11).
      transient do
        testimony_gap_chars { 0 }
      end

      extracted_testimony do
        base = "Testimony submitted at the hearing on this bill."
        next base if testimony_gap_chars.zero?

        base + ("R" * (BillPositionsPromptBuilder.max_testimony_chars + testimony_gap_chars - base.length))
      end

      # A cleaned artifact reporting nothing left
      # out, for the same reason the comment above gives — this trait exists
      # so a fixture can sidestep a gate it isn't testing. Without this,
      # Testimony::CoverageReport reads state: :never_run (the stage never
      # ran on this bill) and ApproveOrgPositionService's sixth refusal fires
      # on every fixture using this trait, whatever it is actually about. A
      # bill meaning to test a real cut, or a genuinely un-cleaned bill,
      # builds its own artifact by hand instead of using this trait.
      cleaned_testimony do
        text = extracted_testimony
        {
          "version" => 1,
          "text" => text,
          "counts" => {"raw_chars" => text.length, "cleaned_chars" => text.length},
          "letters" => [
            {
              "position" => 0, "character_offset" => 0, "characters" => text.length,
              "sender_address" => nil, "sender_domain" => nil,
              "source_kind" => "named_organization", "source_evidence" => nil
            }
          ],
          "campaign_drafts" => []
        }
      end
      cleaned_testimony_at { Time.zone.now }
    end

    trait :pending do
      generation_status { "pending" }
    end

    trait :generating do
      generation_status { "generating" }
    end

    # @lat: [[bill-llm-provisioning-factory-design#:with_testimony and why :with_drafts pulls it in automatically]]
    trait :completed do
      generation_status { "completed" }
      llm_summary { "Test summary" }
      llm_full_breakdown { "## Section 1\nTest" }
    end

    # @lat: [[bill-llm-provisioning-factory-design#:with_testimony and why :with_drafts pulls it in automatically]]
    trait :with_drafts do
      with_testimony

      draft_org_positions do
        [
          {
            "org_name" => "Test Org",
            "stance" => "support",
            "summary" => "Test position"
          }
        ]
      end
    end

    trait :failed do
      generation_status { "failed" }
      generation_error { "Pipeline error: exit code 1" }
    end

    # @lat: [[bill-llm-provisioning-factory-design#:skipped]]
    trait :skipped do
      generation_status { "skipped" }
    end
  end
end
