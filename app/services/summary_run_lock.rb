# frozen_string_literal: true

# @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#One lock shared by the job and the persist guard]]
class SummaryRunLock
  def self.settle_under_lock(provisioning)
    provisioning.restore_attributes if provisioning.changed?
    provisioning.with_lock { yield }
  rescue ActiveRecord::RecordNotFound
    SwayLogging.warn(
      "generate_bill_summary.provisioning_vanished",
      provisioning_id: provisioning.id,
      message: "the provisioning row was deleted while the summary call was in flight"
    )
    nil
  end
end
