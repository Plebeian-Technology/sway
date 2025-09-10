# typed: true
# frozen_string_literal: true

# https://medium.com/@zozulyak.nick/ruby-class-pattern-to-work-with-api-requests-with-built-in-async-approach-bf0713a7dc96

module Scraper
    module Congress
        module Senate
            extend T::Sig

            QUESTIONS = ["on the nomination", "on the joint resolution", "on passage of the bill", 
"on the motion"].freeze

            # https://github.com/LibraryOfCongress/api.congress.gov/issues/64#issuecomment-1403894201
            # https://senate.gov/legislative/LIS/roll_call_votes/vote1182/vote_118_2_00421.xml
            class LegislatorVotes
                include ApiConnector

                def initialize(congress, roll_call_number)
                    @congress = congress # 119
                    @session = Time.zone.now.year.even? ? 2 : 1
                    @roll_call_number = roll_call_number
                end

                def content_type
                    "text/xml"
                end

                def vote_number
                    @roll_call_number&.to_s&.rjust(5, "0")
                end

                # r = Faraday.get('https://www.senate.gov/legislative/LIS/roll_call_lists/vote_menu_118_2.xml')
                # r = Faraday.get('https://www.senate.gov/legislative/LIS/roll_call_votes/vote1182/vote_118_2_00421.xml')
                def do_request
                    return nil unless vote_number

                    get(endpoint)
                end

                # [{"member_full"=>"Casey (D-PA)", "last_name"=>"Casey", "first_name"=>"Bob", "party"=>"D", "state"=>"PA", "vote_cast"=>"Yea", "lis_member_id"=>"S309"},]
                def do_process
                    return [] unless result

                    (result.dig("roll_call_vote", "members", "member") || []).map do |v|
                        Vote.new(v["first_name"], v["last_name"], v["state"], v["party"], v["vote_cast"])
                    end
                end

                private

                def result
                    @result ||= Hash.from_xml(request.value!)
                end

                def endpoint
                    "legislative/LIS/roll_call_votes/vote#{@congress}#{@session}/vote_#{@congress}_#{@session}_#{vote_number}.xml"
                end

                def acceptable_question?(question)
                    QUESTIONS.include?(question.strip.downcase)
                end

                # If no roll_call_number is provided
                # find the latest roll_call_number for the given bill_external_id
                # def get_roll_call_number
                #   return unless @bill_external_id

                #   votes = Votes.new(@congress).process
                #   @vote_number = votes.filter_map do |v|
                #     if acceptable_question?(v['question']) && v['issue'].remove_non_alpha_numeric.downcase == @bill_external_id
                #       v['vote_number'].to_i
                #     end
                #   end.max&.to_s&.rjust(5, '0')
                # end
            end
        end
    end
end
