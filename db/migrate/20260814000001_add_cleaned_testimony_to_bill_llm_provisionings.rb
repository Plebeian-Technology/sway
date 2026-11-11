# frozen_string_literal: true

# Phase 67 D-01: the cleaned artifact sits BESIDE extracted_testimony rather
# than replacing it. FetchHearingsService#persist_testimony! rebuilds
# extracted_testimony from the on-disk .txt sidecars on every fetch run
# (app/services/fetch_hearings_service.rb, around line 1955), so cleaned text
# written into that column would be silently reverted by the next fetch.
#
# cleaned_testimony is :text, not :json — every JSON-holding neighbour on this
# table (draft_org_positions, testimony_attachments, invalid_citations) is
# also t.text; SQLite keeps JSON as plain text regardless of the declared
# column type. cleaned_testimony_at is the freshness marker: the artifact
# describes extracted_testimony as it stood at that moment, and it is stale
# once testimony_fetched_at moves past it.
class AddCleanedTestimonyToBillLlmProvisionings < ActiveRecord::Migration[8.1]
  def change
    add_column :bill_llm_provisionings, :cleaned_testimony, :text
    add_column :bill_llm_provisionings, :cleaned_testimony_at, :datetime
  end
end
