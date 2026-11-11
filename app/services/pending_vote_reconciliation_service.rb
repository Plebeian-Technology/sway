# frozen_string_literal: true

class PendingVoteReconciliationService
  # @lat: [[low-friction-voting#Reconciliation on registration and sign-in]]
  # @lat: [[low-friction-voting#Cast-vote finality and replay protection]]
  # @lat: [[low-friction-voting#Secret ballot preservation and attribution]]

  def self.call(user:, cookies:)
    new(user: user, cookies: cookies).call
  end

  def initialize(user:, cookies:)
    @user = user
    @cookies = cookies
  end

  def call
    raw_data = @cookies.encrypted[:sway_pending_vote]
    @cookies.delete(:sway_pending_vote)
    @cookies.encrypted.delete(:sway_pending_vote) if @cookies.encrypted.respond_to?(:delete)

    return {success: false, reason: :no_pending_vote} if raw_data.blank?

    data = parse_payload(raw_data)
    return {success: false, reason: :invalid_data} unless data.is_a?(Hash)

    bill_id = data["bill_id"] || data[:bill_id]
    support = (data["support"] || data[:support])&.to_s&.upcase&.strip

    return {success: false, reason: :invalid_data} if @user.blank? || bill_id.blank? || support.blank?
    return {success: false, reason: :invalid_data} unless LegislatorVote::Support::FOR_AGAINST.include?(support)

    bill = Bill.find_by(id: bill_id)
    return {success: false, reason: :invalid_data} if bill.nil?
    return {success: false, reason: :bill_inactive} unless bill.active

    existing_vote = UserVote.find_by(user: @user, bill: bill)
    if existing_vote.present?
      if existing_vote.support == support
        return {success: true, status: :already_voted_same, bill: bill}
      else
        return {
          success: false,
          status: :already_voted_different,
          bill: bill,
          message: UserVotesController::VOTE_ALREADY_RECORDED_MESSAGE
        }
      end
    end

    begin
      UserVote.create!(user: @user, bill: bill, support: support)

      if @cookies[:sway_attribution_key].present?
        ArticleEngagementTrackerService.track_vote(
          bill: bill,
          stance: support,
          attribution_key: @cookies[:sway_attribution_key]
        )
      end

      @user.record_funnel_event(:first_vote_cast, {bill_id: bill.id, support: support})

      {success: true, status: :vote_cast, bill: bill}
    rescue ActiveRecord::RecordNotUnique
      existing = UserVote.find_by(user: @user, bill: bill)
      if existing&.support == support
        {success: true, status: :already_voted_same, bill: bill}
      else
        {
          success: false,
          status: :already_voted_different,
          bill: bill,
          message: UserVotesController::VOTE_ALREADY_RECORDED_MESSAGE
        }
      end
    end
  end

  private

  def parse_payload(raw_data)
    if raw_data.is_a?(Hash) && (raw_data.key?(:value) || raw_data.key?("value"))
      raw_data = raw_data[:value] || raw_data["value"]
    end

    if raw_data.is_a?(String)
      JSON.parse(raw_data)
    else
      raw_data
    end
  rescue JSON::ParserError
    nil
  end
end
