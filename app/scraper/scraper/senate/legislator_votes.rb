# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

module Scraper
  module Senate
    extend T::Sig

    # https://github.com/LibraryOfCongress/api.congress.gov/issues/64#issuecomment-1403894201
    # https://senate.gov/legislative/LIS/roll_call_votes/vote1182/vote_118_2_00421.xml
    class LegislatorVotes
      include ApiConnector

      def initialize(congress, bill_external_id)
        @congress = congress # 118
        @session = Date.new.year.even? ? 2 : 1
        @bill_external_id = bill_external_id
        @vote_number = nil
      end

      def content_type
        "text/xml"
      end

      # r = Faraday.get('https://www.senate.gov/legislative/LIS/roll_call_lists/vote_menu_118_2.xml')
      # r = Faraday.get('https://www.senate.gov/legislative/LIS/roll_call_votes/vote1182/vote_118_2_00421.xml')
      def do_request
        votes = Votes.new(@congress).process
        @vote_number = votes.filter_map do |v|
          if acceptable_question?(v['question']) && v['issue'].remove_non_alpha_numeric.downcase == @bill_external_id
            v['vote_number'].to_i
          end
        end.max&.to_s&.rjust(5, '0')

        return nil if @vote_number.nil?

        get(endpoint)
      end

      # [{"member_full"=>"Casey (D-PA)", "last_name"=>"Casey", "first_name"=>"Bob", "party"=>"D", "state"=>"PA", "vote_cast"=>"Yea", "lis_member_id"=>"S309"},]
      def do_process
        return nil unless request

        (result.dig('roll_call_vote', 'members', 'member') || []).map do |v|
          Vote.new(
            v['first_name'],
            v['last_name'],
            v['state'],
            v['party'],
            v['vote_cast']
          )
        end
      end

      private

      def result
        Hash.from_xml(request.value!)
      end

      def endpoint
        "legislative/LIS/roll_call_votes/vote#{@congress}#{@session}/vote_#{@congress}_#{@session}_#{@vote_number}.xml"
      end

      QUESTIONS = [
        'on the nomination',
        'on the joint resolution',
        'on passage of the bill',
        'on the motion'
      ]
      def acceptable_question?(question)
        QUESTIONS.include?(question.strip.downcase)
      end
    end
  end
end
