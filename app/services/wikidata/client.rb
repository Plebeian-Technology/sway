# frozen_string_literal: true

require "json"

# @lat: [[wikidata-open-baltimore-clients-design#Wikidata::Client: reading the sitting mayor]]
module Wikidata
  class Client
    class Error < StandardError; end

    SPARQL_PATH = "sparql"

    HEAD_OF_GOVERNMENT = "P6"
    START_TIME = "P580"
    END_TIME = "P582"

    def initialize(connection: nil)
      @conn = connection || Sway::FaradayStack.wikidata
    end

    def current_head_of_government(city_qid)
      unless city_qid.to_s.match?(/\AQ\d+\z/)
        raise Error, "Wikidata: invalid city entity id #{city_qid.inspect}"
      end

      row = run_query(current_head_of_government_query(city_qid)).first
      return nil if row.nil?

      {
        "name" => row.dig("mayorLabel", "value"),
        "wikidata_id" => row.dig("mayor", "value").to_s.split("/").last,
        "term_start" => row.dig("start", "value")
      }
    end

    private

    def current_head_of_government_query(city_qid)
      <<~SPARQL
        SELECT ?mayor ?mayorLabel ?start WHERE {
          wd:#{city_qid} p:#{HEAD_OF_GOVERNMENT} ?st.
          ?st ps:#{HEAD_OF_GOVERNMENT} ?mayor.
          OPTIONAL { ?st pq:#{START_TIME} ?start. }
          FILTER NOT EXISTS { ?st pq:#{END_TIME} ?end. }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
      SPARQL
    end

    def run_query(sparql)
      response = @conn.get(SPARQL_PATH, query: sparql, format: "json")
      unless response.status.between?(200, 299)
        raise Error, "Wikidata HTTP #{response.status}: #{response.body.to_s[0, 300]}"
      end

      parse_bindings(response.body)
    rescue Faraday::Error => e
      raise Error, "Wikidata transport error: #{e.class.name}: #{e.message.to_s[0, 200]}"
    end

    def parse_bindings(body)
      parsed = body.is_a?(Hash) ? body : JSON.parse(body.to_s)
      Array(parsed.dig("results", "bindings"))
    rescue JSON::ParserError => e
      raise Error, "Wikidata returned a non-JSON body: #{e.message.to_s[0, 200]}"
    end
  end
end
