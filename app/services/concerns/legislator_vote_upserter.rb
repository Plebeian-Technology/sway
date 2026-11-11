# frozen_string_literal: true

# @lat: [[legislator-vote-upserter-guard-rules#Why a guessed vote can never overwrite a real recorded one]]
module LegislatorVoteUpserter
  extend ActiveSupport::Concern

  # @lat: [[legislator-vote-upserter-guard-rules#Why every caller shares one frozen SPONSOR_INFERENCE_VOTE object]]
  SPONSOR_INFERENCE_VOTE = Struct.new(:support).new(LegislatorVote::Support::FOR).freeze

  private

  # @lat: [[legislator-vote-upserter-guard-rules#Why every caller shares one frozen SPONSOR_INFERENCE_VOTE object]]
  def infer_from_sponsors
    legislators = ([@bill.legislator] + @bill.bill_cosponsors.map(&:legislator))
      .compact
      .uniq(&:id)
    legislators.each do |legislator|
      upsert_legislator_vote(legislator.id, SPONSOR_INFERENCE_VOTE, inferred: true)
    end
  end

  # @lat: [[legislator-vote-upserter-guard-rules#Why source: and inferred: default the way they do]]
  def upsert_legislator_vote(legislator_id, vote, source: service_source, inferred: false, legislator_term_id: nil)
    return false if legislator_id.nil?

    if legislator_term_id.nil? && LegislatorVote.column_names.include?("legislator_term_id")
      leg = Legislator.find_by(id: legislator_id)
      return :skipped if leg.nil?

      anchor_date = @bill&.house_vote_date_time_utc || @bill&.senate_vote_date_time_utc || @bill&.introduced_date_time_utc
      covering_term = if anchor_date.present?
        LegislatorTerm.covering(anchor_date, legislator: leg)
      end
      return :skipped if covering_term.nil?

      legislator_term_id = covering_term.id
    end

    existing = LegislatorVote.find_by(bill_id: @bill.id, legislator_id:)
    if existing.nil?
      create_attrs = {
        bill_id: @bill.id,
        support: vote.support,
        legislator_id: legislator_id,
        source: source,
        inferred: inferred
      }
      create_attrs[:legislator_term_id] = legislator_term_id if legislator_term_id.present?
      LegislatorVote.create!(create_attrs)
      true
    elsif existing.source != "manual" || source == "manual"
      # @lat: [[legislator-votes-update-rake-task#Legislator-votes update rake task#Upserter write guard rules]]
      return false if inferred && !existing.inferred

      # @lat: [[legislator-votes-update-rake-task#Legislator-votes update rake task#Upserter write guard rules]]
      update_attrs = {support: vote.support, source: source, inferred: inferred, legislator_term_id: 0}
      if legislator_term_id.present? && existing.respond_to?(:legislator_term_id) && existing.try(:legislator_term_id).nil?
        update_attrs[:legislator_term_id] = legislator_term_id
      else
        update_attrs.delete(:legislator_term_id)
      end
      existing.update!(update_attrs)
      true
    else
      :kept_manual
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Sentry.capture_exception(e, extra: {bill_id: @bill.id, legislator_id:, service: self.class.name})
    SwayLogging.log_exception(
      "legislator_vote_upsert.failed",
      exception: e,
      service: self.class.name,
      bill_id: @bill.id,
      legislator_id: legislator_id
    )
    false
  end

  # @lat: [[legislator-vote-upserter-guard-rules#What each upsert outcome means for vote coverage]]
  def vote_covered?(outcome)
    outcome == true || outcome == :kept_manual
  end

  def service_source
    self.class.const_get(:SERVICE_SOURCE)
  end
end
