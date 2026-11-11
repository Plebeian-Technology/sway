# frozen_string_literal: true

module Scraper
  module Baltimore
    class LegislatorVotes
      FOR_VALUES = %w[yea yes aye].freeze
      AGAINST_VALUES = %w[nay no].freeze

      def initialize(raw_votes:)
        @raw_votes = raw_votes || []
      end

      def process
        @raw_votes.filter_map { |v| map_vote(v) }
      end

      private

      def map_vote(vote)
        value_name = vote["VoteValueName"].to_s.downcase
        support = if FOR_VALUES.include?(value_name)
          ::LegislatorVote::Support::FOR
        elsif AGAINST_VALUES.include?(value_name)
          ::LegislatorVote::Support::AGAINST
        end
        return nil if support.nil?

        Scraper::LegislatorVote.new(
          external_id: vote["VotePersonId"].to_s,
          support: support,
          first_name: "",
          last_name: vote["VotePersonName"].to_s,
          party: "",
          state_code: "MD"
        )
      end
    end
  end
end
