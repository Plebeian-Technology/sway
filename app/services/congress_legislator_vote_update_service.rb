# frozen_string_literal: true

class CongressLegislatorVoteUpdateService
  include LegislatorVoteUpserter

  SERVICE_SOURCE = "congress"

  def self.call(bill_or_id)
    new(bill_or_id).call
  end

  def initialize(bill_or_id)
    @bill = if bill_or_id.is_a?(Bill)
      bill_or_id
    else
      Bill.includes(:sway_locale, :roll_calls, :legislator, bill_cosponsors: :legislator).find(bill_or_id.to_i)
    end
  end

  def call
    # @lat: [[congress-vote-fetch-trigger-architecture#How roll calls are discovered and paced today]]
    rules = @bill.sway_locale.jurisdiction_rules
    vote_src = rules.vote_retrieval&.to_sym
    return unless vote_src == :congress_dot_gov

    senate_error = nil
    begin
      senate
    rescue => e
      senate_error = e
    end

    house_error = nil
    begin
      house
    rescue => e
      house_error = e
    end

    # @lat: [[congress-roll-calls#Why chamber roll-call updates are isolated]]
    infer_from_sponsors if eligible_for_sponsor_inference?(senate_error, house_error)

    # @lat: [[roll-call-identity#Identifying a congressional roll call#Why a wrong roll call raises rather than returns]]
    propagate_errors!(senate_error, house_error)
  end

  private

  # @lat: [[congress-roll-calls#Roll-call numbering restarts every year]]

  def senate
    @senate_upstream_count = 0
    @senate_written_count = 0
    return 0 unless @bill.vote&.senate_roll_call_vote_number

    roll_call_num = @bill.vote.senate_roll_call_vote_number
    year = @bill.senate_vote_date_time_utc&.year
    unless year
      log_missing_vote_date(:senate)
      record_vote_coverage(
        chamber: "senate",
        roll_call_number: roll_call_num,
        eligible_count: 0,
        matched_count: 0,
        unresolved_tokens: [],
        status: coverage_status_missing_vote_date
      )
      return 0
    end

    scraper = Scraper::Congress::Senate::LegislatorVotes
      .new(year: year, roll_call_number: roll_call_num)
    votes = scraper.process
    @senate_upstream_count = votes.size
    identity = scraper.identity
    verify_record!(identity, chamber: :senate, voted_on: @bill.senate_vote_date_time_utc)
    roster = roster_on(identity)
    written_count = 0
    covered_count = 0
    unmatched = []
    votes.each do |vote|
      legislator_id = senator(vote, roster)
      unmatched << vote if legislator_id.nil?
      outcome = upsert_legislator_vote(legislator_id, vote)
      written_count += 1 if outcome == true
      covered_count += 1 if vote_covered?(outcome)
    end
    log_unmatched_voters(:senate, unmatched, votes.size)
    @senate_written_count = written_count

    record_vote_coverage(
      chamber: "senate",
      roll_call_number: roll_call_num,
      eligible_count: votes.size,
      matched_count: covered_count,
      unresolved_tokens: unmatched.map { |v| v.respond_to?(:to_h) ? v.to_h : v },
      status: derive_coverage_status(votes.size, covered_count)
    )

    written_count
  rescue => e
    if @bill.vote&.senate_roll_call_vote_number
      record_vote_coverage(
        chamber: "senate",
        roll_call_number: @bill.vote.senate_roll_call_vote_number,
        eligible_count: @senate_upstream_count.to_i,
        matched_count: @senate_written_count.to_i,
        unresolved_tokens: [],
        status: coverage_status_fetch_failed
      )
    end
    raise e
  end

  def house
    @house_upstream_count = 0
    @house_written_count = 0
    return 0 unless @bill.vote&.house_roll_call_vote_number

    roll_call_num = @bill.vote.house_roll_call_vote_number
    year = @bill.house_vote_date_time_utc&.year
    unless year
      log_missing_vote_date(:house)
      record_vote_coverage(
        chamber: "house",
        roll_call_number: roll_call_num,
        eligible_count: 0,
        matched_count: 0,
        unresolved_tokens: [],
        status: coverage_status_missing_vote_date
      )
      return 0
    end

    scraper = Scraper::Congress::House::LegislatorVotes
      .new(roll_call_number: roll_call_num, year: year)
    votes = scraper.process
    @house_upstream_count = votes.size
    identity = scraper.identity
    verify_record!(identity, chamber: :house, voted_on: @bill.house_vote_date_time_utc)
    roster = roster_on(identity)
    written_count = 0
    covered_count = 0
    unmatched = []
    votes.each do |vote|
      legislator_id = representative(vote, roster)
      unmatched << vote if legislator_id.nil?
      outcome = upsert_legislator_vote(legislator_id, vote)
      written_count += 1 if outcome == true
      covered_count += 1 if vote_covered?(outcome)
    end
    log_unmatched_voters(:house, unmatched, votes.size)
    @house_written_count = written_count

    record_vote_coverage(
      chamber: "house",
      roll_call_number: roll_call_num,
      eligible_count: votes.size,
      matched_count: covered_count,
      unresolved_tokens: unmatched.map { |v| v.respond_to?(:to_h) ? v.to_h : v },
      status: derive_coverage_status(votes.size, covered_count)
    )

    written_count
  rescue => e
    if @bill.vote&.house_roll_call_vote_number
      record_vote_coverage(
        chamber: "house",
        roll_call_number: @bill.vote.house_roll_call_vote_number,
        eligible_count: @house_upstream_count.to_i,
        matched_count: @house_written_count.to_i,
        unresolved_tokens: [],
        status: coverage_status_fetch_failed
      )
    end
    raise e
  end

  # @lat: [[roll-call-identity#Identifying a congressional roll call#Why the record is checked rather than trusted]]
  def verify_record!(identity, chamber:, voted_on:)
    unless identity.taken_on?(voted_on)
      raise Scraper::Congress::RollCallMismatch,
        "#{chamber} roll call for bill #{@bill.external_id} was taken on " \
        "#{identity.voted_on || "no stated day"}, and the bill records " \
        "#{voted_on&.to_date || "none"}"
    end

    verify_question!(identity, chamber: chamber)

    return if identity.names?(@bill.external_id)

    SwayLogging.warn(
      "congress_legislator_votes.record_names_another_document",
      bill_id: @bill.id,
      bill_external_id: @bill.external_id,
      chamber: chamber,
      **identity.to_h
    )
  end

  # @lat: [[congress-roll-calls#A vote on something else is not a position on the bill]]
  def verify_question!(identity, chamber:)
    question = Scraper::Congress::RollCallQuestion.new(
      chamber: chamber, question: identity.question, title: identity.title
    )
    if chamber == :senate && (identity.question.to_s.downcase.include?("cloture") || identity.title.to_s.downcase.include?("cloture"))
      asked = question.to_s.presence || "no stated question"
      raise Scraper::Congress::RollCallNotOnTheBill,
        "#{chamber} roll call for bill #{@bill.external_id} asked #{asked}, which is not a vote on the bill"
    end

    return if question.counts_as_position?

    asked = question.to_s.presence || "no stated question"
    fault = question.known? ? "not a vote on the bill" : "a question Sway does not know"
    raise Scraper::Congress::RollCallNotOnTheBill,
      "#{chamber} roll call for bill #{@bill.external_id} asked #{asked}, which is #{fault}"
  end

  def log_missing_vote_date(chamber)
    SwayLogging.warn(
      "congress_legislator_votes.missing_vote_date",
      bill_id: @bill.id,
      bill_external_id: @bill.external_id,
      chamber: chamber
    )
  end

  # @lat: [[congress-roll-calls#The roster a roll call is matched against is the vote day's]]
  def roster_on(identity)
    day = identity.voted_on ||
      raise(Scraper::Congress::RollCallMismatch,
        "the roll call for bill #{@bill.external_id} states no day")

    LegislatorRoster.new(sway_locale: @bill.sway_locale, on: day)
  end

  def representative(vote, roster)
    roster.with_external_id(vote.external_id)&.legislator_id
  end

  # @lat: [[congress-roll-calls#Nobody is the honest answer when two people cannot be told apart]]
  def senator(vote, roster)
    roster.senator_named(vote.last_name, vote.state_code)&.legislator_id
  end

  # @lat: [[congress-roll-calls#Fetching a Congress roll call]]
  def log_unmatched_voters(chamber, unmatched, published)
    return if unmatched.empty?

    SwayLogging.warn(
      "congress_legislator_votes.voters_not_matched",
      bill_id: @bill.id,
      bill_external_id: @bill.external_id,
      chamber: chamber,
      matched: published - unmatched.size,
      published: published,
      names: unmatched.first(20).map { |vote| "#{vote.last_name} (#{vote.state_code})" }
    )
  end

  def eligible_for_sponsor_inference?(senate_error, house_error)
    return false if senate_error || house_error
    return false if @bill.vote&.senate_roll_call_vote_number.present? && @bill.senate_vote_date_time_utc.blank?
    return false if @bill.vote&.house_roll_call_vote_number.present? && @bill.house_vote_date_time_utc.blank?

    (@senate_upstream_count.to_i + @house_upstream_count.to_i).zero?
  end

  def chamber_outcome(chamber, error, written_count)
    if error
      "#{chamber.to_s.capitalize} refused: #{error.message}"
    elsif @bill.vote&.public_send(:"#{chamber}_roll_call_vote_number").present?
      vote_date = @bill.public_send(:"#{chamber}_vote_date_time_utc")
      if vote_date.blank?
        "#{chamber.to_s.capitalize} skipped: missing vote date"
      else
        "#{chamber.to_s.capitalize} refreshed: #{written_count.to_i} votes"
      end
    else
      "#{chamber.to_s.capitalize} skipped: no roll call"
    end
  end

  def propagate_errors!(senate_error, house_error)
    errors = [senate_error, house_error].compact
    return if errors.empty?

    transport_error = errors.find do |e|
      !e.is_a?(Scraper::Congress::RollCallNotOnTheBill) && !e.is_a?(Scraper::Congress::RollCallMismatch)
    end
    if transport_error
      secondary_error = (errors - [transport_error]).first
      if secondary_error
        secondary_chamber = (secondary_error == senate_error) ? :senate : :house
        SwayLogging.warn(
          "congress_legislator_votes.secondary_chamber_error",
          bill_id: @bill.id,
          bill_external_id: @bill.external_id,
          chamber: secondary_chamber,
          error_class: secondary_error.class.name,
          error_message: secondary_error.message
        )
      end
      raise transport_error
    end

    senate_outcome = chamber_outcome(:senate, senate_error, @senate_written_count)
    house_outcome = chamber_outcome(:house, house_error, @house_written_count)
    composite_message = "#{senate_outcome}; #{house_outcome}"

    if errors.all? { |e| e.is_a?(Scraper::Congress::RollCallMismatch) }
      raise Scraper::Congress::RollCallMismatch, composite_message
    else
      raise Scraper::Congress::RollCallNotOnTheBill, composite_message
    end
  end

  # @lat: [[legislator-vote-upserter-guard-rules#What each upsert outcome means for vote coverage]]
  def derive_coverage_status(total_count, covered_count)
    if total_count.positive? && covered_count == total_count
      defined?(LegislativeVoteCoverage::Status::COMPLETE) ? LegislativeVoteCoverage::Status::COMPLETE : "complete"
    elsif covered_count.positive?
      defined?(LegislativeVoteCoverage::Status::PARTIAL) ? LegislativeVoteCoverage::Status::PARTIAL : "partial"
    else
      defined?(LegislativeVoteCoverage::Status::UNRESOLVED) ? LegislativeVoteCoverage::Status::UNRESOLVED : "unresolved"
    end
  end

  def coverage_status_missing_vote_date
    defined?(LegislativeVoteCoverage::Status::MISSING_VOTE_DATE) ? LegislativeVoteCoverage::Status::MISSING_VOTE_DATE : "missing_vote_date"
  end

  def coverage_status_fetch_failed
    defined?(LegislativeVoteCoverage::Status::FETCH_FAILED) ? LegislativeVoteCoverage::Status::FETCH_FAILED : "fetch_failed"
  end

  def record_vote_coverage(chamber:, roll_call_number:, eligible_count:, matched_count:, unresolved_tokens:, status: nil)
    return unless defined?(LegislativeVoteCoverage)
    return if @bill.nil?

    LegislativeVoteCoverage.record_coverage!(
      bill: @bill,
      chamber: chamber.to_s,
      roll_call_number: roll_call_number.to_s,
      eligible_count: eligible_count,
      matched_count: matched_count,
      unresolved_tokens: unresolved_tokens,
      status: status
    )
  rescue => e
    SwayLogging.warn("congress_legislator_votes.record_coverage_failed", bill_id: @bill&.id, error: e.message)
  end
end
