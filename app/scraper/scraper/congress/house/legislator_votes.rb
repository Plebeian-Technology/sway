# frozen_string_literal: true

require "nokogiri"

module Scraper
  module Congress
    module House
      class LegislatorVotes
        CLERK_BASE_URL = "https://clerk.house.gov"

        SUPPORT_MAP = {
          "Yea" => "FOR",
          "Aye" => "FOR",
          "Nay" => "AGAINST",
          "No" => "AGAINST"
        }.freeze

        # @lat: [[roll-call-identity#Identifying a congressional roll call#Why the year must be the year of the vote]]
        def initialize(roll_call_number:, year:)
          @roll_call_number = roll_call_number
          @year = year.to_i
          @congress = ((@year - 1789) / 2) + 1
          @session = @year.even? ? 2 : 1
        end

        def identity
          raw_result = result
          return Scraper::Congress::RollCallIdentity.new(document_name: nil, question: nil, voted_on: nil) if raw_result.blank?

          if raw_result.is_a?(Hash)
            identity_from_congress_gov(raw_result)
          else
            identity_from_clerk_xml(raw_result)
          end
        end

        def process
          @process ||= do_process
        end

        def do_request
          return nil if @roll_call_number.blank?

          endpoint = "house-vote/#{@congress}/#{@session}/#{@roll_call_number.to_i}/members"
          params = {
            api_key: EnvSecret.congress_gov_api_key!,
            format: :json
          }

          response = Sway::FaradayStack.congress_gov.get(endpoint, params)
          unless response.status == 200
            raise Scraper::Congress::RollCallUnavailable.new(
              chamber: :house,
              congress: @congress,
              session: @session,
              roll_call_number: @roll_call_number.to_i,
              reason: "http_#{response.status}"
            )
          end

          response.body
        end

        def do_process
          raw_result = result
          return [] if raw_result.blank?

          if raw_result.is_a?(Hash)
            process_congress_gov(raw_result)
          else
            process_clerk_xml(raw_result)
          end
        end

        private

        def result
          raise @result_exception if defined?(@result_exception) && @result_exception
          return @result if defined?(@result)
          return @result = nil if @roll_call_number.blank?

          @result = begin
            begin
              fetch_primary
            rescue Scraper::Congress::RollCallUnavailable => e
              primary_error = e.reason
              SwayLogging.warn(
                "house_roll_call.primary_fetch_failed",
                congress: @congress,
                session: @session,
                roll_call_number: @roll_call_number,
                error: primary_error
              )
              fetch_clerk_fallback(primary_error)
            end
          rescue => e
            @result_exception = e
            raise e
          end
        end

        def fetch_primary
          raw = do_request
          return nil if raw.nil?

          parsed =
            if raw.is_a?(Hash)
              raw
            elsif raw.is_a?(String) && raw.present?
              begin
                JSON.parse(raw)
              rescue JSON::ParserError
                nil
              end
            end

          unless parsed.is_a?(Hash) && parsed["houseRollCallVoteMemberVotes"].is_a?(Hash)
            raise Scraper::Congress::RollCallUnavailable.new(
              chamber: :house,
              congress: @congress,
              session: @session,
              roll_call_number: @roll_call_number.to_i,
              reason: "invalid_json"
            )
          end

          parsed
        end

        def fetch_clerk_fallback(primary_error)
          response = clerk_conn.get("evs/#{@year}/roll#{roll}.xml")
          unless response.status == 200
            handle_fallback_failure(primary_error: primary_error, fallback_error: "http_#{response.status}")
          end

          xml_body = response.body.to_s
          doc = Nokogiri.XML(xml_body)
          if xml_body.blank? || doc.at("vote-metadata").nil?
            handle_fallback_failure(primary_error: primary_error, fallback_error: "invalid_xml")
          end

          xml_body
        end

        def handle_fallback_failure(primary_error:, fallback_error:)
          SwayLogging.warn(
            "house_roll_call.fallback_fetch_failed",
            congress: @congress,
            session: @session,
            roll_call_number: @roll_call_number,
            error: fallback_error
          )
          raise Scraper::Congress::RollCallUnavailable.new(
            chamber: :house,
            congress: @congress,
            session: @session,
            roll_call_number: @roll_call_number&.to_i,
            reason: "primary: #{primary_error}, fallback: #{fallback_error}"
          )
        end

        def clerk_conn
          @clerk_conn ||= Sway::FaradayStack.build(
            base_url: CLERK_BASE_URL,
            retry_options: Sway::FaradayStack::OPEN_DATA_DEFAULTS
          )
        end

        def roll
          @roll_call_number.to_s.rjust(3, "0")
        end

        def identity_from_congress_gov(raw_result)
          vote = raw_result["houseRollCallVoteMemberVotes"]
          vote_hash = vote.is_a?(Hash) ? vote : nil

          type = vote_hash ? vote_hash["legislationType"] : nil
          number = vote_hash ? vote_hash["legislationNumber"] : nil

          document_name = if type.present? && number.present?
            "#{type} #{number}"
          end

          Scraper::Congress::RollCallIdentity.new(
            document_name: document_name,
            question: vote_hash ? vote_hash["voteQuestion"] : nil,
            voted_on: parse_date(vote_hash ? vote_hash["startDate"] : nil)
          )
        end

        def identity_from_clerk_xml(xml_content)
          metadata = Nokogiri.XML(xml_content).at("vote-metadata")
          document_name = metadata&.at("legis-num")&.text
          document_name = nil if document_name.blank?

          Scraper::Congress::RollCallIdentity.new(
            document_name: document_name,
            question: metadata&.at("vote-question")&.text,
            voted_on: parse_date(metadata&.at("action-date")&.text)
          )
        end

        def process_congress_gov(raw_result)
          vote = raw_result["houseRollCallVoteMemberVotes"]
          return [] unless vote.is_a?(Hash)

          Array.wrap(vote["results"]).filter_map do |member|
            next unless member.is_a?(Hash)

            support = SUPPORT_MAP[member["voteCast"]]
            external_id = member["bioguideID"].to_s
            first_name = member["firstName"].to_s
            last_name = member["lastName"].to_s
            party = member["voteParty"].to_s
            state_code = member["voteState"].to_s

            next if support.blank? || external_id.blank? || first_name.blank? || last_name.blank? || party.blank? || state_code.blank?

            Scraper::LegislatorVote.new(
              external_id: external_id,
              support: support,
              first_name: first_name,
              last_name: last_name,
              party: party,
              state_code: state_code
            )
          end
        end

        def process_clerk_xml(xml_content)
          Nokogiri.XML(xml_content).search("recorded-vote").filter_map do |vote|
            legislator = vote.at("legislator")
            vote_node = vote.at("vote")
            next if legislator.nil? || vote_node.nil?

            support =
              case vote_node.text&.downcase&.strip
              when "yea", "yes", "aye"
                "FOR"
              when "nay", "no"
                "AGAINST"
              end
            next unless support

            external_id = legislator["name-id"].to_s
            first_name = legislator["first-name"].to_s
            last_name = (legislator["last-name"].presence || legislator["unaccented-name"].presence || legislator["sort-field"].presence || legislator.text.to_s.strip).to_s
            party = legislator["party"].to_s
            state_code = legislator["state"].to_s

            next if external_id.blank? || last_name.blank? || party.blank? || state_code.blank?

            Scraper::LegislatorVote.new(
              external_id: external_id,
              support: support,
              first_name: first_name,
              last_name: last_name,
              party: party,
              state_code: state_code
            )
          end
        end

        # @lat: [[congress-roll-calls#Why parse date rescues ArgumentError]]
        def parse_date(text)
          return nil if text.blank?

          Date.parse(text.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
