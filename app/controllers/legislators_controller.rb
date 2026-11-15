# frozen_string_literal: true

class LegislatorsController < ApplicationController
  before_action :set_legislator, only: %i[show]
  skip_before_action :authenticate_sway_user!, only: %i[show]

  # @lat: [[lazy-inertia-props#The Legislators index applies the same rule]]
  def index
    render_inertia_or_json(
      page: Pages::LEGISLATORS,
      props: {
        legislators: json_legislators,
        waiting_for_new_term: -> { waiting_for_new_term? },
        filters: -> { {search: legislators_search_param} },
        **history_prop
      }
    )
  end

  # @lat: [[legislators-controller-design#Detail page has its own response]]
  def show
    render_inertia_or_json(
      page: Pages::LEGISLATOR,
      props: {
        legislator: legislator_with_score(@legislator)
      }
    )
  end

  private

  def set_legislator
    # @lat: [[legislators-controller-design#Active term is loaded before detail serialization]]
    @legislator = Legislator.with_term_history.find(params[:id])
  end

  # @lat: [[legislators-controller-design#Why waiting_for_new_term distinguishes empty list causes]]
  def waiting_for_new_term?
    return false if json_legislators.any?
    return false if current_user.nil? || current_sway_locale.nil?

    current_user
      .user_legislators
      .joins(:legislator)
      .where(active: true)
      .where(legislators: {sway_locale_id: current_sway_locale.id})
      .exists?
  end

  # @lat: [[legislators-controller-design#List data is reused within one request]]
  def json_legislators
    @json_legislators ||= build_json_legislators
  end

  def build_json_legislators
    empty_scores = []
    # @type var empty_scores: Array[untyped]

    return empty_scores unless current_user&.user_legislators&.any? && current_sway_locale.present?

    # @lat: [[legislators-controller-design#Representative rows stay within the viewed locale]]
    user_legislators = current_user
      .user_legislators
      .joins(legislator: :active_term)
      .includes(
        {user_legislator_term_scores: :legislator_term},
        legislator: [
          {active_term: {district: :sway_locale}},
          {district: :sway_locale},
          {photo_attachment: :blob},
          {legislator_terms: [
            :seat,
            {district: :sway_locale},
            :legislator_district_scores,
            :legislator_locale_scores
          ]}
        ]
      )
      .where(active: true)
      .where(legislators: {sway_locale_id: current_sway_locale.id})
      .distinct
      .to_a

    legislator_ids = user_legislators.map(&:legislator_id)
    explanations_by_legislator_id =
      if current_user && legislator_ids.any? && HistoricalScoreExplanation.table_exists?
        HistoricalScoreExplanation
          .where(user_id: current_user.id, legislator_id: legislator_ids)
          .group_by(&:legislator_id)
      else
        {}
      end

    user_legislators.each do |user_legislator|
      terms_by_id = user_legislator.legislator.legislator_terms.index_by(&:id)
      user_legislator.user_legislator_term_scores.each do |uts|
        matched_term = terms_by_id[uts.legislator_term_id]
        uts.legislator_term = matched_term if matched_term
      end
    end

    user_legislators.map do |user_legislator|
      explanations = explanations_by_legislator_id[user_legislator.legislator_id] || []
      legislator_score_payload(user_legislator, historical_score_explanations: explanations)
    end
  end

  # @lat: [[legislators-controller-design#Score props retain their established shape]]
  def legislator_with_score(legislator)
    user_legislator =
      current_user&.user_legislators&.includes(user_legislator_term_scores: :legislator_term)&.find_by(legislator_id: legislator.id)

    if user_legislator
      user_legislator.legislator = legislator
      terms_by_id = legislator.legislator_terms.index_by(&:id)
      user_legislator.user_legislator_term_scores.each do |uts|
        matched_term = terms_by_id[uts.legislator_term_id]
        uts.legislator_term = matched_term if matched_term
      end
    end

    user_scores_by_term_id =
      user_legislator ? user_legislator.user_legislator_term_scores.index_by(&:legislator_term_id) : {}

    explanations =
      if current_user && HistoricalScoreExplanation.table_exists?
        HistoricalScoreExplanation.where(user_id: current_user.id, legislator_id: legislator.id).to_a
      else
        []
      end

    payload = LegislatorResource.new(
      legislator,
      params: {
        current_user: current_user,
        user_legislator: user_legislator,
        user_legislator_term_scores: user_scores_by_term_id,
        historical_score_explanations: explanations
      }
    ).serializable_hash #: Hash[Symbol, untyped]

    score_props =
      if user_legislator
        user_legislator_score_pair(user_legislator)
      else
        {user_legislator_score: nil, lifetime_score: nil}
      end

    payload.merge(
      **score_props,
      bill_of_the_month_votes: bill_of_the_month_votes_for(legislator)
    )
  end

  # @lat: [[legislators-controller-design#Bill of the Month voting record lives on the detail payload]]
  def bill_of_the_month_votes_for(legislator)
    bills = Bill
      .where(sway_locale_id: legislator.sway_locale_id, scheduled_release_date_utc: ..Time.zone.today)
      .order(scheduled_release_date_utc: :desc, id: :desc)
      .to_a
    return [] if bills.empty?

    legislator_votes_by_bill_id = LegislatorVote
      .where(legislator_id: legislator.id, bill_id: bills.map(&:id))
      .index_by(&:bill_id)

    # @lat: [[legislators-controller-design#Bill of the Month voting record lives on the detail payload#Term and chamber eligibility filter]]
    eligibility = LegislatorBillEligibility.new(legislator)
    eligible_bills = bills.select do |bill|
      eligibility.eligible?(bill:, has_recorded_vote: legislator_votes_by_bill_id.key?(bill.id))
    end
    return [] if eligible_bills.empty?

    user = current_user
    user_votes_by_bill_id =
      if user
        UserVote.where(user_id: user.id, bill_id: eligible_bills.map(&:id)).index_by(&:bill_id)
      else
        {}
      end

    LegislatorBillOfTheMonthVoteResource.new(
      eligible_bills,
      params: {
        legislator_votes_by_bill_id: legislator_votes_by_bill_id,
        user_votes_by_bill_id: user_votes_by_bill_id
      }
    ).serializable_hash #: Array[Hash[Symbol, untyped]]
  end

  # @lat: [[legislators-controller-design#Score props retain their established shape]]
  def legislator_score_payload(user_legislator, historical_score_explanations: [])
    user_scores = user_legislator.user_legislator_term_scores.index_by(&:legislator_term_id)
    hash = LegislatorResource.new(
      user_legislator.legislator,
      params: {
        current_user: current_user,
        user_legislator: user_legislator,
        user_legislator_term_scores: user_scores,
        historical_score_explanations: historical_score_explanations
      }
    ).serializable_hash #: Hash[Symbol, untyped]
    hash.merge(user_legislator_score_pair(user_legislator))
  end

  # @lat: [[scores-and-agreement#Executive offices and reader agreement]]
  def user_legislator_score_pair(user_legislator)
    current_score = current_term_score_for(user_legislator)

    {
      user_legislator_score: current_score && UserLegislatorTermScoreResource.new(current_score).serializable_hash,
      lifetime_score: UserLegislatorTermScoreResource.lifetime_hash_for(user_legislator)
    }
  end

  # @lat: [[scores-and-agreement#Every score is bound to a term]]
  def current_term_score_for(user_legislator)
    rows = user_legislator.user_legislator_term_scores.to_a
    active_term = user_legislator.legislator.active_term

    if user_legislator.active && active_term
      rows.find { |uts| uts.legislator_term_id == active_term.id }
    else
      rows.max_by { |uts| uts.legislator_term.term_start_year }
    end
  end

  # @lat: [[legislators-controller-design#History is resolved only when requested]]
  def history_payload
    return {sessions: [], legislative_sessions: []} unless current_user && current_sway_locale

    LegislatorHistoryResource
      .new(current_user, params: {sway_locale: current_sway_locale})
      .serializable_hash
  end

  # @lat: [[legislators-controller-design#Forced history failure is test-only]]
  def history_prop
    attempt = forced_history_error_attempt
    if attempt
      {errors: {history: "Simulated history load failure (test-only) attempt=#{attempt}"}}
    elsif legislators_tab_param == "history"
      # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
      {history: history_payload}
    else
      {history: InertiaRails.optional { history_payload }}
    end
  end

  # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
  def legislators_tab_param
    params.key?(:legislators_tab) ? params[:legislators_tab] : params[:tab]
  end

  # @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
  def legislators_search_param
    params.key?(:legislators_search) ? params[:legislators_search] : params[:search]
  end

  # @lat: [[legislators-controller-design#Forced history failure is test-only]]
  def forced_history_error_attempt
    return nil unless Rails.env.test? && params[:_test_force_history_error].present?
    return nil unless requesting_history_partial_reload?

    session[:_test_history_error_attempt] = session[:_test_history_error_attempt].to_i + 1
  end

  def requesting_history_partial_reload?
    request.headers["X-Inertia-Partial-Data"].to_s.split(",").include?("history")
  end
end
