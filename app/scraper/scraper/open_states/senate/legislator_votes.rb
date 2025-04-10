# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

module Scraper
  module OpenStates
    module Senate
      extend T::Sig

      # https://v3.openstates.org/redoc#tag/bills/operation/bill_detail_bills__jurisdiction___session___bill_id__get
      class LegislatorVotes
        include ApiConnector

        def initialize(region_code, bill_created_at_year, external_bill_id)
          @region_code = region_code # 119
          @bill_created_at_year = bill_created_at_year
          @external_bill_id = external_bill_id
        end

        def content_type
          "application/json"
        end

        def vote_number
          # @roll_call_number&.to_s&.rjust(5, "0")
        end

        def do_request
          return nil unless vote_number

          get(endpoint)
        end

        # "votes": [
        # {
        #     "id": "f0049138-1ad8-4506-a2a4-f4dd1251bbba",
        #     "option": "no",
        #     "voter_name": "Wu",
        #     "voter":
        # {
        #     "id": "ocd-person/adb58f21-f2fd-4830-85b6-f490b0867d14",
        #     "name": "Angela Augusta",
        #     "party": "Democratic",
        #     "current_role":
        #             {
        #                 "title": "Senator",
        #                 "org_classification": "upper",
        #                 "district": 3,
        #                 "division_id": "ocd-division/country:us/state:nc/sldu:3"
        #             }
        #         }
        #     }
        # ],
        def do_process
          return [] unless result

          (result.dig(:votes) || []).map do |v_|
            v = v_.deep_symbolize_keys
            support = if v[:option]&.lower == "no"
              "AGAINST"
            elsif v[:option]&.lower == "yes"
              "FOR"
            end

            if support.present?
              Vote.new(v.dig(:voter, :id), support)
            end
          end.compact
        end

        private

        def result
          Rails.logger.info("Scraper::OpenStates::Senate.result - Request URL - #{endpoint}")
          @result ||= JSON.parse(request.value!).dig(:votes, 0)
        end

        def endpoint
          "/bills/#{@region_code}/#{@bill_created_at_year}/#{@external_bill_id}"
        end
      end
    end
  end
end
