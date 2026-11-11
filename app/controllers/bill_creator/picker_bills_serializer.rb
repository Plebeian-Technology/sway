# frozen_string_literal: true

# @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
module BillCreator
  class PickerBillsSerializer
    # @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
    def self.call(scope, locale:)
      bills = Bill.arel_table
      legislators = Legislator.arel_table
      vote_tally = Arel.sql(
        "(SELECT COUNT(*) FROM legislator_votes WHERE legislator_votes.bill_id = bills.id)"
      )
      position_tally = Arel.sql(
        "(SELECT COUNT(*) FROM organization_bill_positions " \
        "WHERE organization_bill_positions.bill_id = bills.id AND organization_bill_positions.active)"
      )
      # @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
      latest_score_signals = Arel.sql(
        "(SELECT signals FROM bill_interesting_scores s " \
        "WHERE s.bill_id = bills.id ORDER BY s.id DESC LIMIT 1)"
      )

      # @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
      rules = locale&.declared_jurisdiction_rules
      publishes_legislator_votes = rules ? rules.publishes_legislator_votes : false
      theoretical_max = BillInterestingScoreCalculator.theoretical_max(publishes_legislator_votes)

      scope
        .joins(:legislator)
        .pluck(
          bills[:id],
          bills[:external_id],
          bills[:title],
          bills[:scheduled_release_date_utc],
          bills[:status],
          bills[:chamber],
          bills[:category],
          bills[:introduced_date_time_utc],
          bills[:house_vote_date_time_utc],
          bills[:senate_vote_date_time_utc],
          legislators[:first_name],
          legislators[:last_name],
          vote_tally,
          position_tally,
          latest_score_signals
        )
        .map do |id, external_id, title, scheduled, status, chamber, category, introduced, house_vote, senate_vote, first_name, last_name, vote_count, position_count, signals_json|
          # @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
          signals = rules.nil? ? nil : parse_signals(signals_json, id)
          latest_action_date = latest_action_date_time(introduced, house_vote, senate_vote)
          fresh = fresh_timeliness(latest_action_date)

          {
            id: id,
            external_id: external_id,
            title: title,
            scheduled_release_date_utc: scheduled&.iso8601,
            status: status,
            chamber: chamber,
            category: category,
            introduced_date_time_utc: introduced&.iso8601,
            # @lat: [[bill-creator-shell#The Bill Creator shell#Why the admin picker sorts by introduction date]]
            latest_action_date_time_utc: latest_action_date&.iso8601,
            sponsor_name: "#{first_name} #{last_name}",
            legislator_vote_count: vote_count,
            organization_position_count: position_count,
            interesting_score_normalized: interesting_score_normalized(signals, fresh, theoretical_max),
            interesting_badges: interesting_badges(signals, publishes_legislator_votes, fresh)
          }
        end
    end

    # @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
    def self.parse_signals(signals_json, bill_id)
      return nil if signals_json.nil?

      JSON.parse(signals_json)
    rescue JSON::ParserError => e
      SwayLogging.warn(
        "BillCreator::PickerBillsSerializer - corrupt bill_interesting_scores.signals JSON for bill #{bill_id}: #{e.message}"
      )
      nil
    end

    # @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
    def self.latest_action_date_time(introduced, house_vote, senate_vote)
      [introduced, house_vote, senate_vote].compact.max #: Time?
    end

    # @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
    def self.fresh_timeliness(most_recent)
      return 0.0 if most_recent.nil?

      days_ago = (Time.current - most_recent) / 86_400.0
      fraction = (1.0 - (days_ago / BillInterestingScoreCalculator::TIMELINESS_WINDOW_DAYS)).clamp(0.0, 1.0)
      fraction * BillInterestingScoreCalculator::WEIGHT_TIMELINESS
    end

    # @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
    def self.interesting_score_normalized(signals, fresh_timeliness, theoretical_max)
      return nil if signals.nil?

      effective_raw = signals["vote_defection_score"].to_f +
        signals["vote_abstention_score"].to_f +
        signals["org_split_score"].to_f +
        signals["testimony_engagement_score"].to_f +
        fresh_timeliness
      (effective_raw / theoretical_max).clamp(0.0, 1.0)
    end

    # @lat: [[bill-interesting-score#The bill interesting score#Picker reads]]
    def self.interesting_badges(signals, publishes_legislator_votes, fresh_timeliness)
      return [] if signals.nil?

      badges = [] #: Array[("controversial" | "close" | "live")]
      if signals["vote_defection_score"].to_f > 0 || signals["org_split_score"].to_f > 0
        badges << "controversial"
      end
      if publishes_legislator_votes
        real_for = signals["real_for"].to_i
        real_against = signals["real_against"].to_i
        total_cast = real_for + real_against
        if total_cast > 0 &&
            ((real_for - real_against).abs.to_f / total_cast) <= BillInterestingScoreCalculator::CLOSE_MARGIN_THRESHOLD
          badges << "close"
        end
      end
      badges << "live" if fresh_timeliness > 0
      badges
    end
  end
end
