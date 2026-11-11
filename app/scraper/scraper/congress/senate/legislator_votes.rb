# frozen_string_literal: true

module Scraper
  module Congress
    module Senate
      class LegislatorVotes
        include ApiConnector

        VOTEVIEW_BASE_URL = "https://voteview.com"
        VOTEVIEW_CACHE_TTL = 6.hours
        VOTEVIEW_CACHE_FRESHNESS_WINDOW = 15.minutes

        PARTY_MAP = {
          "Democrat" => "D",
          "Republican" => "R",
          "Independent" => "I"
        }.freeze

        # @lat: [[roll-call-identity#Identifying a congressional roll call#Why the year must be the year of the vote]]
        def initialize(year:, roll_call_number:)
          year = year.to_i
          @congress = ((year - 1789) / 2) + 1
          @session = year.even? ? 2 : 1
          @roll_call_number = roll_call_number
        end

        def identity
          body = result
          vote = body.is_a?(Hash) ? body["roll_call_vote"] : nil
          vote = {} unless vote.is_a?(Hash)
          # @lat: [[roll-call-identity#Identifying a congressional roll call#Why the record is checked rather than trusted]]
          document = vote["document"]
          document = {} unless document.is_a?(Hash)

          Scraper::Congress::RollCallIdentity.new(
            document_name: document["document_name"],
            question: vote["question"],
            title: vote["vote_title"],
            voted_on: parse_date(vote["vote_date"])
          )
        end

        def content_type
          "text/xml"
        end

        def vote_number
          return nil if @roll_call_number.blank?

          @roll_call_number.to_s.rjust(5, "0")
        end

        def do_request
          return nil unless vote_number

          get(endpoint)
        end

        def do_process
          raw_result = result
          return [] unless raw_result

          Array.wrap(raw_result.dig("roll_call_vote", "members", "member")).filter_map do |v|
            support =
              case v["vote_cast"]&.downcase&.strip
              when "yea", "yes", "aye", "1"
                "FOR"
              when "nay", "no", "6"
                "AGAINST"
              end
            next unless support

            Scraper::LegislatorVote.new(
              external_id: v["lis_member_id"].to_s,
              support: support,
              first_name: v["first_name"].to_s,
              last_name: v["last_name"].to_s,
              party: v["party"].to_s,
              state_code: v["state"].to_s
            )
          end
        end

        private

        def result
          raise @failure_exception if defined?(@failure_exception) && @failure_exception
          return @result if defined?(@result)
          return @result = nil if @roll_call_number.blank?

          primary_data = fetch_primary_xml
          return @result = primary_data if primary_data

          SwayLogging.warn(
            "senate_roll_call.primary_fetch_failed",
            congress: @congress,
            session: @session,
            roll_call_number: @roll_call_number,
            error: @primary_error || "primary_fetch_returned_nil"
          )

          fallback_data = fetch_voteview_fallback
          return @result = fallback_data if fallback_data

          primary_err = @primary_error || "primary_fetch_returned_nil"
          fallback_err = @fallback_error || "unknown_fallback_failure"
          reason = "primary: #{primary_err}, fallback: #{fallback_err}"

          @failure_exception = Scraper::Congress::RollCallUnavailable.new(
            chamber: :senate,
            congress: @congress,
            session: @session,
            roll_call_number: @roll_call_number.to_i,
            reason: reason
          )
          raise @failure_exception
        end

        def fetch_primary_xml
          return nil if @roll_call_number.blank?

          raw = request.value!
          if raw.blank?
            @primary_error = "blank_response"
            return nil
          end

          if html_response?(raw)
            @primary_error = "html_challenge"
            return nil
          end

          parsed = Hash.from_xml(raw)
          unless parsed.is_a?(Hash) && parsed["roll_call_vote"].is_a?(Hash)
            @primary_error = "missing_roll_call_vote"
            return nil
          end

          parsed
        rescue Scraper::FaradayConnector::ClientError,
          Scraper::FaradayConnector::ServerError,
          Scraper::FaradayConnector::TimeoutError,
          Faraday::Error,
          REXML::ParseException => e
          @primary_error = "#{e.class}: #{e.message}"
          nil
        end

        def html_response?(raw)
          raw.is_a?(String) && raw.match?(/\A\s*(?:<!DOCTYPE\s+html|<html)/i)
        end

        def fetch_voteview_fallback
          return nil if @roll_call_number.blank?

          entry = resolve_voteview_entry
          return nil unless entry && entry["rollnumber"]

          rollcall_id = "RS#{@congress}#{entry["rollnumber"].to_s.rjust(4, "0")}"
          dl_response = voteview_conn.get("api/download", {rollcall_id: rollcall_id})
          unless dl_response.status == 200
            handle_fallback_failure("download_http_#{dl_response.status}")
            return nil
          end

          dl_data = dl_response.body.is_a?(String) ? JSON.parse(dl_response.body) : dl_response.body
          unless dl_data.is_a?(Hash)
            handle_fallback_failure("invalid_download_format")
            return nil
          end

          rollcall = Array(dl_data["rollcalls"]).first
          unless rollcall.is_a?(Hash)
            handle_fallback_failure("missing_rollcall_in_download")
            return nil
          end

          normalize_voteview_rollcall(rollcall)
        rescue Faraday::Error, JSON::ParserError => e
          handle_fallback_failure("#{e.class}: #{e.message}")
          nil
        end

        def resolve_voteview_entry
          cache_key = "voteview/senate_rollcalls/#{@congress}"
          cached = Rails.cache.read(cache_key)

          if cached.is_a?(Hash)
            cached_data = cached[:data] || cached["data"]
            if cached_data.is_a?(Array)
              entry = find_rollcall_in_index(cached_data)
              return entry if entry

              fetched_at = cached[:fetched_at] || cached["fetched_at"]
              if fetched_at.present? && fetched_at > VOTEVIEW_CACHE_FRESHNESS_WINDOW.ago
                handle_fallback_failure("roll_call_not_found_in_voteview_index")
                return nil
              end
            end
          end

          fetch_and_cache_voteview_index(cache_key)
        end

        def fetch_and_cache_voteview_index(cache_key)
          index_response = voteview_conn.get("static/data/out/rollcalls/S#{@congress}_rollcalls.json")
          unless index_response.status == 200
            handle_fallback_failure("index_http_#{index_response.status}")
            return nil
          end

          index_data = index_response.body.is_a?(String) ? JSON.parse(index_response.body) : index_response.body
          unless index_data.is_a?(Array)
            handle_fallback_failure("invalid_index_format")
            return nil
          end

          compact_data = compact_index_entries(index_data)
          Rails.cache.write(
            cache_key,
            {fetched_at: Time.current, data: compact_data},
            expires_in: VOTEVIEW_CACHE_TTL
          )

          entry = find_rollcall_in_index(compact_data)
          unless entry
            handle_fallback_failure("roll_call_not_found_in_voteview_index")
            return nil
          end

          entry
        end

        def compact_index_entries(index_data)
          index_data.filter_map do |e|
            next unless e.is_a?(Hash) && e["session"] && e["clerk_rollnumber"] && e["rollnumber"]

            {
              "session" => e["session"].to_i,
              "clerk_rollnumber" => e["clerk_rollnumber"].to_i,
              "rollnumber" => e["rollnumber"].to_i
            }
          end
        end

        def find_rollcall_in_index(index_entries)
          index_entries.find do |e|
            e.is_a?(Hash) && e["session"] == @session && e["clerk_rollnumber"] == @roll_call_number.to_i
          end
        end

        def voteview_conn
          @voteview_conn ||= Sway::FaradayStack.build(
            base_url: VOTEVIEW_BASE_URL,
            retry_options: Sway::FaradayStack::OPEN_DATA_DEFAULTS
          )
        end

        def normalize_voteview_rollcall(rollcall)
          return nil unless rollcall.is_a?(Hash)

          members = Array(rollcall["votes"]).filter_map do |v|
            next unless v.is_a?(Hash)

            party = PARTY_MAP[v["party_name"]] ||
              PARTY_MAP[v["party"]] ||
              (v["party_short_name"].present? ? v["party_short_name"].to_s[0] : nil) ||
              (v["party"].present? ? v["party"].to_s[0] : nil)

            state = v["state_abbrev"].presence || v["state"]
            vote_cast = if v["cast_str"].present?
              v["cast_str"]
            elsif v["vote"].to_s == "1"
              "Yea"
            elsif v["vote"].to_s == "6"
              "Nay"
            else
              v["vote"]
            end

            {
              "lis_member_id" => v["lis_member_id"].to_s,
              "first_name" => v["first_name"].to_s,
              "last_name" => v["last_name"].to_s,
              "party" => party.to_s,
              "state" => state.to_s,
              "vote_cast" => vote_cast.to_s
            }
          end

          {
            "roll_call_vote" => {
              "document" => {"document_name" => rollcall["bill_number"]},
              "question" => rollcall["question"],
              "vote_title" => rollcall["vote_title"],
              "vote_date" => rollcall["date"],
              "members" => {
                "member" => members
              }
            }
          }
        end

        def handle_fallback_failure(error_details)
          @fallback_error = error_details
          SwayLogging.warn(
            "senate_roll_call.fallback_fetch_failed",
            congress: @congress,
            session: @session,
            roll_call_number: @roll_call_number,
            error: error_details
          )
        end

        def endpoint
          "legislative/LIS/roll_call_votes/vote#{@congress}#{@session}/vote_#{@congress}_#{@session}_#{vote_number}.xml"
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
