# frozen_string_literal: true

# @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
# @lat: [[current-legislator-term#Which term a legislator is serving now#The vote-entry roster is everyone who ever held the seat#Matching a name resolves against the roster of the vote's own day]]
class GenericLegislatorVoteUpdateService
  include LegislatorVoteUpserter

  SERVICE_SOURCE = "generic"
  MATTER_FILE_PATTERN = /\A[A-Za-z0-9-]+\z/

  Result = Data.define(:written_count, :unmatched_count, :inferred)

  attr_reader :bill, :source
  attr_writer :open_legislator_client, :legistar_client

  def self.call(bill: nil, votes: nil, infer_sponsors_if_empty: true, source: nil)
    new(bill, source: source).call(votes: votes, infer_sponsors_if_empty: infer_sponsors_if_empty, source: source)
  end

  def initialize(bill_or_id = nil, source: nil)
    @bill = bill_or_id.is_a?(Integer) ? Bill.find_by(id: bill_or_id) : bill_or_id
    @source = source
  end

  def call(bill: nil, votes: nil, infer_sponsors_if_empty: true, source: nil)
    @source = source if source.present?
    if bill.present?
      @bill = bill.is_a?(Integer) ? Bill.find_by(id: bill) : bill
    end
    raise ArgumentError, "Bill is required" if @bill.nil?

    votes_array = Array(votes)
    if votes_array.empty?
      if infer_sponsors_if_empty
        infer_from_sponsors
        apply_final_passage_outcome if should_apply_final_passage?
        return Result.new(written_count: 0, unmatched_count: 0, inferred: true)
      end
      apply_final_passage_outcome if should_apply_final_passage?
      return Result.new(written_count: 0, unmatched_count: 0, inferred: false)
    end

    written_count = 0
    covered_count = 0
    unmatched_votes = []
    roster_cache = {}
    has_missing_date = false

    begin
      votes_array.each do |vote_data|
        next unless vote_data.is_a?(Hash) || vote_data.respond_to?(:to_h)

        vote_hash =
          if vote_data.is_a?(Hash)
            vote_data.deep_symbolize_keys
          elsif vote_data.respond_to?(:to_h)
            vote_data.to_h.deep_symbolize_keys
          else
            {}
          end

        next if vote_hash.blank? || (vote_hash[:legislator_external_id].blank? && vote_hash[:external_id].blank? && vote_hash[:last_name].blank? && vote_hash[:legislator_id].blank?)

        raw_voted_on = vote_hash[:voted_on] || @bill&.vote_date_time_utc
        voted_on = resolve_vote_date(raw_voted_on)
        has_missing_date = true if voted_on.nil?

        legislator_id = resolve_legislator_id(vote_hash, roster_cache, voted_on: voted_on)
        if legislator_id.nil?
          unmatched_votes << vote_hash
          next
        end

        support_val = normalize_support(vote_hash[:vote_value] || vote_hash[:support])
        vote_obj = Struct.new(:support).new(support_val)

        # @lat: [[legislator-vote-upserter-guard-rules#Why LegislatorVoteUpserter guards writes the way it does]]
        outcome = upsert_legislator_vote(legislator_id, vote_obj, source: service_source)
        written_count += 1 if outcome == true
        covered_count += 1 if vote_covered?(outcome)
      end

      if unmatched_votes.any?
        log_unmatched_votes(unmatched_votes, votes_array.size)
      end

      # @lat: [[legislator-vote-upserter-guard-rules#What each upsert outcome means for vote coverage]]
      status = if has_missing_date && votes_array.any?
        defined?(LegislativeVoteCoverage::Status::MISSING_VOTE_DATE) ? LegislativeVoteCoverage::Status::MISSING_VOTE_DATE : "missing_vote_date"
      elsif covered_count == votes_array.size
        defined?(LegislativeVoteCoverage::Status::COMPLETE) ? LegislativeVoteCoverage::Status::COMPLETE : "complete"
      elsif covered_count.positive?
        defined?(LegislativeVoteCoverage::Status::PARTIAL) ? LegislativeVoteCoverage::Status::PARTIAL : "partial"
      else
        defined?(LegislativeVoteCoverage::Status::UNRESOLVED) ? LegislativeVoteCoverage::Status::UNRESOLVED : "unresolved"
      end

      record_vote_coverage(
        eligible_count: votes_array.size,
        matched_count: covered_count,
        unresolved_tokens: unmatched_votes,
        status: status
      )

      Result.new(written_count: written_count, unmatched_count: unmatched_votes.size, inferred: false)
    rescue => e
      record_vote_coverage(
        eligible_count: votes_array.size,
        matched_count: covered_count,
        unresolved_tokens: unmatched_votes,
        status: defined?(LegislativeVoteCoverage::Status::FETCH_FAILED) ? LegislativeVoteCoverage::Status::FETCH_FAILED : "fetch_failed"
      )
      raise e
    end
  end

  private

  def service_source
    rules = @bill&.sway_locale&.jurisdiction_rules&.vote_rules || {}
    source = (rules[:source] || rules["source"] || rules[:retrieval] || rules["retrieval"] || rules[:engine] || rules["engine"]).to_s
    source = "congress" if source == "congress_dot_gov" || source == "generic_csv"
    LegislatorVote::SOURCES.include?(source) ? source : SERVICE_SOURCE
  end

  def configured_timezone
    locale = @bill&.sway_locale
    rules = locale&.jurisdiction_rules
    tz_name = if rules
      if rules.respond_to?(:vote_timezone)
        rules.vote_timezone
      elsif rules.respond_to?(:vote_rules) && rules.vote_rules
        rules.vote_rules[:timezone] || rules.vote_rules["timezone"]
      end
    end
    tz_name ||= (locale.time_zone.presence if locale.respond_to?(:time_zone))
    return nil if tz_name.blank?

    ActiveSupport::TimeZone[tz_name] || Time.find_zone(tz_name)
  end

  def resolve_vote_date(raw_date)
    return nil if raw_date.blank?
    return raw_date if raw_date.is_a?(Date) && !raw_date.is_a?(DateTime)

    tz = configured_timezone

    if raw_date.is_a?(String)
      if raw_date.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        begin
          return Date.iso8601(raw_date)
        rescue ArgumentError
          return nil
        end
      end

      time_obj = begin
        Time.iso8601(raw_date)
      rescue ArgumentError
        begin
          Time.zone.parse(raw_date)
        rescue ArgumentError, TypeError
          begin
            Date.parse(raw_date)
          rescue ArgumentError
            nil
          end
        end
      end
    else
      time_obj = raw_date
    end

    return nil if time_obj.blank?
    return time_obj if time_obj.is_a?(Date) && !time_obj.is_a?(DateTime)

    if tz && time_obj.respond_to?(:in_time_zone)
      time_obj.in_time_zone(tz).to_date
    elsif time_obj.respond_to?(:to_date)
      time_obj.to_date
    end
  end

  def historical_fallback_enabled?
    rules = @bill&.sway_locale&.jurisdiction_rules
    return false if rules.nil?

    if rules.respond_to?(:enable_historical_fallback?)
      rules.enable_historical_fallback?
    elsif rules.respond_to?(:enable_historical_fallback)
      rules.enable_historical_fallback == true
    elsif rules.respond_to?(:vote_rules) && rules.vote_rules.is_a?(Hash)
      rules.vote_rules[:enable_historical_fallback] == true ||
        rules.vote_rules["enable_historical_fallback"] == true
    else
      false
    end
  end

  def attempt_historical_import(vote_hash, voted_on)
    return false unless defined?(HistoricalElectedOfficialImporter)
    return false if @bill&.sway_locale.nil?

    ext_id = vote_hash[:legislator_external_id] || vote_hash[:external_id]
    return false if ext_id.blank?

    clues = {
      external_id: ext_id,
      bioguide_id: vote_hash[:bioguide_id] || ext_id,
      last_name: vote_hash[:last_name],
      first_name: vote_hash[:first_name],
      state: vote_hash[:state] || vote_hash[:state_code],
      chamber: vote_hash[:chamber] || @bill&.chamber
    }.compact

    result = HistoricalElectedOfficialImporter.new(sway_locale: @bill.sway_locale).call(
      jurisdiction: @bill.sway_locale,
      identity_clues: clues,
      vote_day: voted_on
    )

    result.respond_to?(:success?) && result.success?
  rescue => e
    SwayLogging.warn("generic_legislator_votes.historical_import_failed", external_id: ext_id, error: e.message)
    false
  end

  def record_vote_coverage(eligible_count:, matched_count:, unresolved_tokens:, status: nil)
    return unless defined?(LegislativeVoteCoverage)

    bill = @bill
    return if bill.nil?

    chamber = bill.chamber.presence || "council"
    bill_vote = bill.vote
    roll_call = if bill_vote
      if bill_vote.respond_to?(:roll_call_number)
        bill_vote.public_send(:roll_call_number)
      elsif bill_vote.respond_to?(:house_roll_call_vote_number) && bill_vote.house_roll_call_vote_number
        bill_vote.house_roll_call_vote_number
      elsif bill_vote.respond_to?(:senate_roll_call_vote_number) && bill_vote.senate_roll_call_vote_number
        bill_vote.senate_roll_call_vote_number
      else
        bill.external_id
      end
    else
      bill.external_id
    end
    roll_call = (roll_call.presence || "1").to_s

    LegislativeVoteCoverage.record_coverage!(
      bill: bill,
      chamber: chamber,
      roll_call_number: roll_call,
      eligible_count: eligible_count,
      matched_count: matched_count,
      unresolved_tokens: unresolved_tokens,
      status: status
    )
  rescue => e
    SwayLogging.warn("generic_legislator_votes.record_coverage_failed", bill_id: @bill&.id, error: e.message)
  end

  def resolve_legislator_id(vote_hash, roster_cache, voted_on: nil)
    return vote_hash[:legislator_id] if vote_hash[:legislator_id].present?

    sway_locale = @bill&.sway_locale
    return nil if sway_locale.nil?

    ext_id = vote_hash[:legislator_external_id] || vote_hash[:external_id]
    voted_on ||= resolve_vote_date(vote_hash[:voted_on] || @bill&.vote_date_time_utc)

    if ext_id.present?
      if voted_on && defined?(LegislatorRoster)
        roster = (roster_cache[voted_on] ||= LegislatorRoster.new(sway_locale: sway_locale, on: voted_on))
        matched_term = roster.with_external_id(ext_id)
        return matched_term.legislator_id if matched_term
      end

      direct = Legislator.find_by(sway_locale: sway_locale, external_id: ext_id)
      return direct.id if direct

      if historical_fallback_enabled? && voted_on && attempt_historical_import(vote_hash, voted_on)
        if defined?(LegislatorRoster)
          roster_cache[voted_on] = LegislatorRoster.new(sway_locale: sway_locale, on: voted_on)
          matched_term = roster_cache[voted_on].with_external_id(ext_id)
          return matched_term.legislator_id if matched_term
        end

        direct = Legislator.find_by(sway_locale: sway_locale, external_id: ext_id)
        return direct.id if direct
      end
    end

    if vote_hash[:last_name].present? && vote_hash[:state_code].present? && voted_on && defined?(LegislatorRoster)
      roster = (roster_cache[voted_on] ||= LegislatorRoster.new(sway_locale: sway_locale, on: voted_on))
      matched_senator = roster.senator_named(vote_hash[:last_name], vote_hash[:state_code])
      return matched_senator.legislator_id if matched_senator
    end

    nil
  end

  def normalize_support(raw)
    case raw.to_s.strip.downcase
    when "yea", "yes", "aye", "for"
      LegislatorVote::Support::FOR
    when "nay", "no", "against"
      LegislatorVote::Support::AGAINST
    else
      LegislatorVote::Support::ABSTAIN
    end
  end

  def log_unmatched_votes(unmatched, total)
    SwayLogging.warn(
      "generic_legislator_votes.voters_not_matched",
      bill_id: @bill&.id,
      bill_external_id: @bill&.external_id,
      matched: total - unmatched.size,
      total: total,
      unmatched_ids: unmatched.map { |v| v[:legislator_external_id] || v[:last_name] }
    )
  end

  def should_apply_final_passage?
    return false if @bill.nil? || @bill.external_id.blank?
    return true if open_legislator_source?

    rules = @bill.sway_locale&.jurisdiction_rules
    return false if rules.nil?

    retrieval = (rules.respond_to?(:retrieval_for) ? rules.retrieval_for(:vote) : nil) ||
      rules.vote_rules&.dig(:retrieval)&.to_s ||
      rules.vote_rules&.dig("retrieval")&.to_s ||
      rules.vote_rules&.dig(:engine)&.to_s ||
      rules.vote_rules&.dig("engine")&.to_s
    retrieval == "legistar" || rules.final_passage_action_ids.present?
  end

  def open_legislator_source?
    return true if @source.to_s == "open_legislator"

    rules = @bill&.sway_locale&.jurisdiction_rules
    return false if rules.nil?

    retrieval = (rules.respond_to?(:retrieval_for) ? rules.retrieval_for(:vote) : nil) ||
      rules.vote_rules&.dig(:source)&.to_s ||
      rules.vote_rules&.dig("source")&.to_s ||
      rules.vote_rules&.dig(:retrieval)&.to_s ||
      rules.vote_rules&.dig("retrieval")&.to_s
    retrieval == "open_legislator"
  end

  def apply_final_passage_outcome
    bill = @bill
    return if bill.nil?

    if open_legislator_source?
      handled = apply_open_legislator_final_passage
      return if handled
    end

    apply_legistar_final_passage
  end

  def apply_open_legislator_final_passage
    bill = @bill
    return false if bill.nil?

    matter = begin
      open_legislator_client.matter_by_file_number(bill.external_id)
    rescue OpenLegislator::Client::Error, Faraday::Error => e
      SwayLogging.warn(
        "[GenericLegislatorVoteUpdateService] Open Legislator lookup error for bill_id=#{bill.id} " \
          "external_id=#{bill.external_id}: #{e.message} — falling back to Legistar"
      )
      return false
    end

    if matter.nil?
      SwayLogging.warn(
        "[GenericLegislatorVoteUpdateService] Open Legislator matter not found for bill_id=#{bill.id} " \
          "external_id=#{bill.external_id} — falling back to Legistar"
      )
      return false
    end

    actions = Array(matter["actions"]).select { |a| a.is_a?(Hash) }
    passage_action = actions.select do |a|
      res = a["result"].to_s.strip.downcase
      name = a["action_name"].to_s.strip.downcase
      res == "pass" || name.include?("pass") || name.include?("adopt") || name.include?("enact") || name.include?("favor")
    end.max_by { |a| a["acted_on"].to_s }

    enacted_outcome = matter["status"].is_a?(Hash) && matter["status"]["outcome"].to_s.strip.downcase == "enacted"

    raw_date = passage_action&.dig("acted_on")
    raw_date ||= matter["enacted_on"] if enacted_outcome
    raw_date ||= matter["final_action_on"] if enacted_outcome

    if raw_date.present?
      date = raw_date.is_a?(String) ? Time.zone.parse(raw_date) : raw_date
      if date.present?
        bill.update!(house_vote_date_time_utc: date)
        return true
      end
    end

    SwayLogging.info(
      "[GenericLegislatorVoteUpdateService] bill_id=#{bill.id} external_id=#{bill.external_id} " \
        "matter found in Open Legislator (slug=#{matter["slug"].inspect}) but has no passing action or enacted outcome — " \
        "honest no-op, preserving house_vote_date_time_utc"
    )
    true
  rescue ArgumentError => e
    SwayLogging.warn(
      "[GenericLegislatorVoteUpdateService] bill_id=#{bill.id} unparseable date #{raw_date.inspect}: #{e.message} — skipping"
    )
    true
  rescue ActiveRecord::RecordInvalid => e
    SwayLogging.warn(
      "[GenericLegislatorVoteUpdateService] bill_id=#{bill.id} cannot write final passage date: #{e.record.errors.full_messages.join("; ")} — skipping"
    )
    true
  end

  def apply_legistar_final_passage
    bill = @bill
    return if bill.nil?

    matter_id = resolve_matter_id
    return if matter_id.nil?

    histories = legistar_client.matter_histories(matter_id)
    row = latest_final_passage_row(histories)
    return if row.nil?

    write_final_passage_date(matter_id, row)
  rescue ArgumentError, Legistar::Client::Error => e
    SwayLogging.warn(
      "[GenericLegislatorVoteUpdateService] Legistar final passage lookup failed for bill_id=#{bill.id}: #{e.message}"
    )
  end

  def write_final_passage_date(matter_id, row)
    bill = @bill
    return if bill.nil?

    raw_date = row["MatterHistoryActionDate"]
    date = raw_date.is_a?(String) ? Time.zone.parse(raw_date) : nil

    if date.nil?
      SwayLogging.warn(
        "[GenericLegislatorVoteUpdateService] bill_id=#{bill.id} matter_id=#{matter_id} " \
          "final-passage row (MatterHistoryId=#{row["MatterHistoryId"].inspect}, " \
          "MatterHistoryActionId=#{row["MatterHistoryActionId"].inspect}) has a missing/" \
          "unparseable MatterHistoryActionDate=#{raw_date.inspect} — internally-inconsistent " \
          "Legistar data, skipping the vote-date write"
      )
      return
    end

    bill.update!(house_vote_date_time_utc: date)
  rescue ArgumentError => e
    SwayLogging.warn(
      "[GenericLegislatorVoteUpdateService] bill_id=#{@bill&.id} matter_id=#{matter_id} " \
        "unparseable MatterHistoryActionDate=#{raw_date.inspect}: #{e.message.to_s[0, 200]} — skipping"
    )
  rescue ActiveRecord::RecordInvalid => e
    SwayLogging.warn(
      "[GenericLegislatorVoteUpdateService] bill_id=#{@bill&.id} matter_id=#{matter_id} " \
        "cannot write the final-passage date because the bill is already invalid on another " \
        "column: #{e.record.errors.full_messages.join("; ")} — skipping; the row needs repairing " \
        "at source"
    )
  end

  def resolve_matter_id
    bill = @bill
    return nil if bill.nil?

    external_id = bill.external_id.to_s.strip

    unless external_id.match?(MATTER_FILE_PATTERN)
      SwayLogging.warn(
        "[GenericLegislatorVoteUpdateService] bill_id=#{bill.id} external_id=#{external_id.inspect} " \
          "fails the Baltimore MatterFile shape guard — skipping matter_id resolution (no client call)"
      )
      return nil
    end

    matters = legistar_client.matters(filter: "MatterFile eq '#{external_id}'")
    rows = matters.is_a?(Array) ? matters : []
    row = rows.first
    matter_id = row.is_a?(Hash) ? row["MatterId"] : nil

    unless matter_id.is_a?(Integer) && matter_id.positive?
      SwayLogging.warn(
        "[GenericLegislatorVoteUpdateService] bill_id=#{bill.id} external_id=#{external_id} " \
          "did not resolve to a Legistar MatterId (matters lookup returned #{matters.inspect[0, 200]}) — " \
          "honest no-op, sponsor-inference still runs"
      )
      return nil
    end

    matter_id
  end

  def latest_final_passage_row(histories)
    return nil unless histories.is_a?(Array)

    bill = @bill
    return nil if bill.nil?

    action_ids = bill.sway_locale&.jurisdiction_rules&.final_passage_action_ids
    if action_ids.blank?
      SwayLogging.warn(
        "[GenericLegislatorVoteUpdateService] bill_id=#{bill.id} locale=#{bill.sway_locale&.name} " \
          "has no final_passage_action_ids declared — skipping passage-date write"
      )
      return nil
    end

    candidates = histories.select do |row|
      row.is_a?(Hash) && action_ids.include?(row["MatterHistoryActionId"])
    end
    return nil if candidates.empty?

    candidates.max_by { |row| [row["MatterHistoryActionDate"].to_s, row["MatterHistoryId"].to_i] }
  end

  def legistar_client
    @legistar_client ||= begin
      rules = @bill&.sway_locale&.jurisdiction_rules
      client_name = rules&.vote_rules&.dig(:client) ||
        rules&.vote_rules&.dig("client") ||
        rules&.legislation_rules&.dig(:client) ||
        rules&.legislation_rules&.dig("client") ||
        (@bill&.sway_locale&.city if @bill&.sway_locale.respond_to?(:city))
      raise ArgumentError, "No client configured for Legistar vote update" if client_name.blank?
      Legistar::Client.new(client: client_name.to_s)
    end
  end

  def open_legislator_client
    @open_legislator_client ||= begin
      rules = @bill&.sway_locale&.jurisdiction_rules
      base_url = rules&.vote_rules&.dig(:open_legislator_base_url) ||
        rules&.vote_rules&.dig("open_legislator_base_url") ||
        Sway::Settings.upstream.open_legislator_base_url
      OpenLegislator::Client.new(base_url: base_url)
    end
  end
end
