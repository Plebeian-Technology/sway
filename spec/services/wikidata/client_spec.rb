# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wikidata::Client do
  subject(:client) { described_class.new }

  let(:endpoint) { "https://query.wikidata.org/sparql" }

  def stub_sparql(body:, status: 200)
    stub_request(:get, endpoint)
      .with(query: hash_including("format" => "json"))
      .to_return(status: status, body: body, headers: {"Content-Type" => "application/sparql-results+json"})
  end

  describe "#current_head_of_government" do
    it "returns the sitting officeholder's name, entity id, and term start" do
      stub_sparql(body: {
        "results" => {
          "bindings" => [
            {
              "mayor" => {"type" => "uri", "value" => "http://www.wikidata.org/entity/Q66363416"},
              "mayorLabel" => {"type" => "literal", "value" => "Brandon Scott"},
              "start" => {"type" => "literal", "value" => "2020-12-08T00:00:00Z"}
            }
          ]
        }
      }.to_json)

      result = client.current_head_of_government("Q5092")

      expect(result).to eq(
        "name" => "Brandon Scott",
        "wikidata_id" => "Q66363416",
        "term_start" => "2020-12-08T00:00:00Z"
      )
    end

    it "returns nil when Wikidata lists no current officeholder" do
      stub_sparql(body: {"results" => {"bindings" => []}}.to_json)

      expect(client.current_head_of_government("Q5092")).to be_nil
    end

    it "raises on a malformed city entity id without hitting the network" do
      expect { client.current_head_of_government("Q5092; DROP") }
        .to raise_error(described_class::Error, /invalid city entity id/)
    end

    it "raises on a non-2xx response" do
      stub_sparql(body: "rate limited", status: 429)

      expect { client.current_head_of_government("Q5092") }.to raise_error(described_class::Error, /HTTP 429/)
    end

    it "raises on a non-JSON body" do
      stub_sparql(body: "<html>busy</html>")

      expect { client.current_head_of_government("Q5092") }.to raise_error(described_class::Error, /non-JSON/)
    end
  end
end
