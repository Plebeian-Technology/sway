# frozen_string_literal: true

require "rails_helper"

# @lat: [[jurisdiction-rules#Jurisdiction declarations]]
RSpec.describe SwayLocale::JurisdictionRules do
  def jurisdiction_rules_with(overrides = {}) #: (?Hash[Symbol, untyped]) -> SwayLocale::JurisdictionRules
    described_class.new(
      publishes_legislator_votes: false,
      chamber_label: "City Council",
      session_numbering: :term_years,
      default_bill_chamber: "council",
      bill_chambers: %w[council],
      **overrides
    )
  end

  describe "legacy source properties removal" do
    let(:rules) { jurisdiction_rules_with }

    it "does not respond to deleted legacy source readers and helper methods" do
      target_rules = jurisdiction_rules_with
      %i[
        roster_source
        roster_refresher
        vote_source
        legistar_client
        legistar_client!
        open_states_jurisdiction
        open_states_jurisdiction!
        legislation_source
        law_source
        hearings_source
      ].each do |method_name|
        expect(target_rules.respond_to?(method_name)).to be(false), "expected rules not to respond to #{method_name}"
        expect { target_rules.public_send(method_name) }.to raise_error(NoMethodError)
      end
    end

    it "refuses legacy initialization parameters" do
      legacy_kwargs = [
        {roster_source: :curated},
        {roster_refresher: :baltimore},
        {vote_source: :legistar},
        {legistar_client: "baltimore"},
        {open_states_jurisdiction: "Maryland"},
        {legislation_source: :legistar},
        {law_source: :baltimore_legref},
        {hearings_source: :legistar}
      ]

      legacy_kwargs.each do |kwarg|
        expect {
          jurisdiction_rules_with(kwarg)
        }.to raise_error(ArgumentError, /unknown keyword/), "expected #{kwarg.keys.first} to be rejected"
      end
    end
  end

  # @lat: [[jurisdiction-rules#Jurisdiction declarations#Declared bill chambers]]
  describe "the chambers a bill here can be in" do
    it "carries the list the jurisdiction declared" do
      expect(jurisdiction_rules_with(bill_chambers: %w[council]).bill_chambers).to eq(%w[council])
    end

    it "does not freeze the array it was given" do
      chambers = %w[house senate both]

      jurisdiction_rules_with(default_bill_chamber: "house", bill_chambers: chambers)

      expect(chambers).not_to be_frozen
    end

    it "refuses a default the jurisdiction does not have" do
      expect { jurisdiction_rules_with(default_bill_chamber: "senate", bill_chambers: %w[council]) }
        .to raise_error(ArgumentError, /is not one of this jurisdiction's chambers/)
    end
  end

  describe "accepted_matter_types" do
    it "defaults to empty array when unspecified" do
      rules = jurisdiction_rules_with
      expect(rules.accepted_matter_types).to eq([])
    end

    it "does not fall back to ['Ordinance'] when client is baltimore in legislation_rules without accepted_matter_types" do
      rules = jurisdiction_rules_with(legislation_rules: {client: "baltimore"})
      expect(rules.accepted_matter_types).to eq([])
    end

    it "reads accepted_matter_types configured inside legislation_rules and freezes the array" do
      rules = jurisdiction_rules_with(legislation_rules: {accepted_matter_types: %w[Ordinance Resolution]})
      expect(rules.accepted_matter_types).to eq(%w[Ordinance Resolution])
      expect(rules.accepted_matter_types).to be_frozen
    end

    it "carries declared matter types and freezes the array" do
      rules = jurisdiction_rules_with(accepted_matter_types: %w[Bill Resolution])
      expect(rules.accepted_matter_types).to eq(%w[Bill Resolution])
      expect(rules.accepted_matter_types).to be_frozen
    end
  end

  describe "final_passage_action_ids" do
    it "is nil when unspecified" do
      rules = jurisdiction_rules_with
      expect(rules.final_passage_action_ids).to be_nil
    end

    it "carries custom declared final passage action IDs" do
      rules = described_class.new(
        publishes_legislator_votes: false,
        chamber_label: "City Council",
        session_numbering: :term_years,
        default_bill_chamber: "council",
        bill_chambers: %w[council],
        final_passage_action_ids: [10, 20, 30]
      )
      expect(rules.final_passage_action_ids).to eq([10, 20, 30])
      expect(rules.final_passage_action_ids).to be_frozen
    end
  end

  describe "integration rules accessors" do
    it "defaults all integration rules to nil" do
      rules = jurisdiction_rules_with
      expect(rules.legislation_rules).to be_nil
      expect(rules.hearings_rules).to be_nil
      expect(rules.vote_rules).to be_nil
      expect(rules.roster_rules).to be_nil
      expect(rules.law_rules).to be_nil
    end

    it "stores and exposes provided integration rules in frozen form with symbolized keys" do
      leg_rules = {"engine" => "generic_rest", "base_url" => "https://example.com", "metadata_mapping" => {"id" => "$.id"}}
      rules = described_class.new(
        publishes_legislator_votes: false,
        chamber_label: "City Council",
        session_numbering: :term_years,
        default_bill_chamber: "council",
        bill_chambers: %w[council],
        legislation_rules: leg_rules,
        hearings_rules: {engine: "generic_html", base_url: "https://example.com/h"},
        vote_rules: {engine: "generic_csv", base_url: "https://example.com/v"},
        roster_rules: {engine: "generic_graphql", base_url: "https://example.com/r"},
        law_rules: {engine: "generic_rest", base_url: "https://example.com/l"}
      )

      expect(rules.legislation_rules).to eq({
        engine: "generic_rest",
        base_url: "https://example.com",
        metadata_mapping: {id: "$.id"}
      })
      expect(rules.legislation_rules).to be_frozen
      expect(rules.hearings_rules&.[](:engine)).to eq("generic_html")
      expect(rules.vote_rules&.[](:engine)).to eq("generic_csv")
      expect(rules.roster_rules&.[](:engine)).to eq("generic_graphql")
      expect(rules.law_rules&.[](:engine)).to eq("generic_rest")
    end

    it "prevents external mutation of passed integration rules" do
      leg_rules = {engine: "generic_rest", base_url: "https://example.com"}
      rules = described_class.new(
        publishes_legislator_votes: false,
        chamber_label: "City Council",
        session_numbering: :term_years,
        default_bill_chamber: "council",
        bill_chambers: %w[council],
        legislation_rules: leg_rules
      )

      leg_rules[:engine] = "mutated"
      expect(rules.legislation_rules&.[](:engine)).to eq("generic_rest")
    end
  end

  describe "retrieval and parsing accessors" do
    describe "domain-specific accessors" do
      it "falls back to engine when retrieval and parsing are not explicitly configured" do
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council],
          legislation_rules: {engine: "generic_rest", base_url: "https://example.com/leg"},
          hearings_rules: {engine: "generic_html", base_url: "https://example.com/hear"},
          vote_rules: {engine: "generic_csv", base_url: "https://example.com/vote"},
          roster_rules: {engine: "generic_graphql", base_url: "https://example.com/roster"},
          law_rules: {engine: "akoma_ntoso", base_url: "https://example.com/law"}
        )
        expect(rules.legislation_retrieval).to eq("generic_rest")
        expect(rules.legislation_parsing).to eq("generic_rest")
        expect(rules.hearings_retrieval).to eq("generic_html")
        expect(rules.hearings_parsing).to eq("generic_html")
        expect(rules.vote_retrieval).to eq("generic_csv")
        expect(rules.vote_parsing).to eq("generic_csv")
        expect(rules.roster_retrieval).to eq("generic_graphql")
        expect(rules.roster_parsing).to eq("generic_graphql")
        expect(rules.law_retrieval).to eq("akoma_ntoso")
        expect(rules.law_parsing).to eq("akoma_ntoso")
      end

      it "returns explicit retrieval and parsing values taking precedence over legacy engine" do
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council],
          legislation_rules: {retrieval: "generic_rest", parsing: "generic_json", engine: "legacy_engine"},
          hearings_rules: {retrieval: "generic_http", parsing: "html_table"},
          vote_rules: {retrieval: "rest_api", parsing: "csv_stream"},
          roster_rules: {retrieval: "graphql_api", parsing: "member_nodes"},
          law_rules: {retrieval: "git_repo", parsing: "akoma_ntoso_xml"}
        )
        expect(rules.legislation_retrieval).to eq("generic_rest")
        expect(rules.legislation_parsing).to eq("generic_json")
        expect(rules.hearings_retrieval).to eq("generic_http")
        expect(rules.hearings_parsing).to eq("html_table")
        expect(rules.vote_retrieval).to eq("rest_api")
        expect(rules.vote_parsing).to eq("csv_stream")
        expect(rules.roster_retrieval).to eq("graphql_api")
        expect(rules.roster_parsing).to eq("member_nodes")
        expect(rules.law_retrieval).to eq("git_repo")
        expect(rules.law_parsing).to eq("akoma_ntoso_xml")
      end

      it "supports retrieval_strategy and parser_format aliases" do
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council],
          legislation_rules: {retrieval_strategy: "rest_v2", parser_format: "json_v2"},
          hearings_rules: {retrieval_strategy: "html_fetch", parser_format: "event_dom"},
          vote_rules: {retrieval_strategy: "csv_download", parser_format: "tabular"},
          roster_rules: {retrieval_strategy: "graphql_query", parser_format: "nested_roster"},
          law_rules: {retrieval_strategy: "xml_pull", parser_format: "statute_tree"}
        )
        expect(rules.legislation_retrieval).to eq("rest_v2")
        expect(rules.legislation_parsing).to eq("json_v2")
        expect(rules.hearings_retrieval).to eq("html_fetch")
        expect(rules.hearings_parsing).to eq("event_dom")
        expect(rules.vote_retrieval).to eq("csv_download")
        expect(rules.vote_parsing).to eq("tabular")
        expect(rules.roster_retrieval).to eq("graphql_query")
        expect(rules.roster_parsing).to eq("nested_roster")
        expect(rules.law_retrieval).to eq("xml_pull")
        expect(rules.law_parsing).to eq("statute_tree")
      end

      it "supports aliases with _rules_ infix" do
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council],
          legislation_rules: {retrieval: "generic_rest", parsing: "generic_json"},
          hearings_rules: {retrieval: "generic_http", parsing: "html_table"},
          vote_rules: {retrieval: "rest_api", parsing: "csv_stream"},
          roster_rules: {retrieval: "graphql_api", parsing: "member_nodes"},
          law_rules: {retrieval: "git_repo", parsing: "akoma_ntoso_xml"}
        )
        expect(rules.legislation_rules_retrieval).to eq("generic_rest")
        expect(rules.legislation_rules_parsing).to eq("generic_json")
        expect(rules.hearings_rules_retrieval).to eq("generic_http")
        expect(rules.hearings_rules_parsing).to eq("html_table")
        expect(rules.vote_rules_retrieval).to eq("rest_api")
        expect(rules.vote_rules_parsing).to eq("csv_stream")
        expect(rules.roster_rules_retrieval).to eq("graphql_api")
        expect(rules.roster_rules_parsing).to eq("member_nodes")
        expect(rules.law_rules_retrieval).to eq("git_repo")
        expect(rules.law_rules_parsing).to eq("akoma_ntoso_xml")
      end
    end

    describe "generic retrieval_for and parsing_for methods" do
      it "queries rule domains by symbol or string with or without _rules suffix" do
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council],
          legislation_rules: {retrieval: "generic_rest", parsing: "generic_json"},
          hearings_rules: {retrieval: "generic_http", parsing: "html_table"},
          vote_rules: {retrieval: "rest_api", parsing: "csv_stream"},
          roster_rules: {retrieval: "graphql_api", parsing: "member_nodes"},
          law_rules: {retrieval: "git_repo", parsing: "akoma_ntoso_xml"}
        )
        %i[legislation hearings vote roster law].each do |domain|
          expect(rules.retrieval_for(domain)).to be_present
          expect(rules.retrieval_for(:"#{domain}_rules")).to be_present
          expect(rules.retrieval_for(domain.to_s)).to be_present
          expect(rules.parsing_for(domain)).to be_present
          expect(rules.parsing_for(:"#{domain}_rules")).to be_present
          expect(rules.parsing_for(domain.to_s)).to be_present
        end
      end

      it "aliases retrieval and parsing to retrieval_for and parsing_for" do
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council],
          legislation_rules: {retrieval: "generic_rest", parsing: "generic_json"}
        )
        expect(rules.retrieval(:legislation)).to eq("generic_rest")
        expect(rules.parsing(:legislation)).to eq("generic_json")
      end

      it "raises ArgumentError when an unknown rule domain is requested" do
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council]
        )
        expect { rules.retrieval_for(:unknown) }
          .to raise_error(ArgumentError, /Unknown rule domain: :unknown/)
        expect { rules.parsing_for(:unknown) }
          .to raise_error(ArgumentError, /Unknown rule domain: :unknown/)
        expect { rules.retrieval_for(nil) }
          .to raise_error(ArgumentError, /Unknown rule domain: nil/)
        expect { rules.parsing_for("") }
          .to raise_error(ArgumentError, /Unknown rule domain: ""/)
      end

      it "supports plural domain aliases (:votes, :laws, 'votes_rules', 'laws_rules') and deep-freezes nested structures" do
        nested_rules = {
          retrieval: "generic_rest",
          parsing: "generic_json",
          nested_hash: {key: "val"},
          nested_array: [{item: 1}]
        }
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council],
          legislation_rules: nested_rules,
          vote_rules: {retrieval: "rest_api", parsing: "csv_stream"},
          law_rules: {retrieval: "git_repo", parsing: "akoma_ntoso_xml"}
        )

        expect(rules.retrieval_for(:votes)).to eq("rest_api")
        expect(rules.parsing_for(:votes)).to eq("csv_stream")
        expect(rules.retrieval_for("votes_rules")).to eq("rest_api")
        expect(rules.parsing_for("votes_rules")).to eq("csv_stream")
        expect(rules.retrieval_for(:laws)).to eq("git_repo")
        expect(rules.parsing_for(:laws)).to eq("akoma_ntoso_xml")
        expect(rules.retrieval_for("laws_rules")).to eq("git_repo")
        expect(rules.parsing_for("laws_rules")).to eq("akoma_ntoso_xml")

        expect(rules.bill_chambers).to be_frozen
        expect(rules.legislation_rules[:nested_hash]).to be_frozen
        expect(rules.legislation_rules[:nested_array]).to be_frozen
        expect(rules.legislation_rules[:nested_array].first).to be_frozen
      end
    end

    describe "graceful handling of missing and blank values" do
      it "returns nil when a rule domain is nil or empty" do
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council],
          legislation_rules: nil,
          hearings_rules: {}
        )
        expect(rules.legislation_retrieval).to be_nil
        expect(rules.legislation_parsing).to be_nil
        expect(rules.hearings_retrieval).to be_nil
        expect(rules.hearings_parsing).to be_nil
      end

      it "falls back to engine when retrieval or parsing is an empty or whitespace string" do
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council],
          legislation_rules: {retrieval: "   ", parsing: "", engine: "fallback_engine"}
        )
        expect(rules.legislation_retrieval).to eq("fallback_engine")
        expect(rules.legislation_parsing).to eq("fallback_engine")
      end

      it "returns nil when both explicit properties and engine are blank" do
        rules = described_class.new(
          publishes_legislator_votes: false,
          chamber_label: "City Council",
          session_numbering: :term_years,
          default_bill_chamber: "council",
          bill_chambers: %w[council],
          legislation_rules: {retrieval: "   ", parsing: nil, engine: ""}
        )
        expect(rules.legislation_retrieval).to be_nil
        expect(rules.legislation_parsing).to be_nil
      end
    end
  end

  describe "#legacy_path_fallback?" do
    it "returns true when legislation_rules has legacy_path_fallback: true" do
      rules = jurisdiction_rules_with(legislation_rules: {legacy_path_fallback: true})
      expect(rules.legacy_path_fallback?).to be(true)
    end

    it "returns true when legislation_rules has 'legacy_path_fallback' string key true" do
      rules = jurisdiction_rules_with(legislation_rules: {"legacy_path_fallback" => true})
      expect(rules.legacy_path_fallback?).to be(true)
    end

    it "returns false when legislation_rules is nil or does not include legacy_path_fallback" do
      rules = jurisdiction_rules_with(legislation_rules: nil)
      expect(rules.legacy_path_fallback?).to be(false)

      rules2 = jurisdiction_rules_with(legislation_rules: {retrieval: "legistar"})
      expect(rules2.legacy_path_fallback?).to be(false)
    end
  end

  describe "#testimony_classification_enabled?" do
    it "returns true when testimony_rules has enable_classification: true" do
      rules = jurisdiction_rules_with(testimony_rules: {enable_classification: true})
      expect(rules.testimony_classification_enabled?).to be(true)
    end

    it "returns true when testimony_rules has 'enable_classification' string key true" do
      rules = jurisdiction_rules_with(testimony_rules: {"enable_classification" => true})
      expect(rules.testimony_classification_enabled?).to be(true)
    end

    it "returns false when testimony_rules has enable_classification: false" do
      rules = jurisdiction_rules_with(testimony_rules: {enable_classification: false})
      expect(rules.testimony_classification_enabled?).to be(false)
    end

    it "returns false when testimony_rules is nil or does not include enable_classification" do
      rules = jurisdiction_rules_with(testimony_rules: nil)
      expect(rules.testimony_classification_enabled?).to be(false)

      rules2 = jurisdiction_rules_with(testimony_rules: {})
      expect(rules2.testimony_classification_enabled?).to be(false)
    end
  end

  describe "#generic_portal_urls" do
    it "returns generic_portal_urls array from legislation_rules" do
      rules = jurisdiction_rules_with(
        legislation_rules: {generic_portal_urls: ["https://example.gov", "https://example.gov/search"]}
      )
      expect(rules.generic_portal_urls).to eq(["https://example.gov", "https://example.gov/search"])
      expect(rules.generic_portal_urls).to be_frozen
    end

    it "returns generic_portal_urls array from string-keyed legislation_rules" do
      rules = jurisdiction_rules_with(
        legislation_rules: {"generic_portal_urls" => ["https://example.gov"]}
      )
      expect(rules.generic_portal_urls).to eq(["https://example.gov"])
    end

    it "returns empty array when legislation_rules is nil or generic_portal_urls is omitted" do
      rules = jurisdiction_rules_with(legislation_rules: nil)
      expect(rules.generic_portal_urls).to eq([])

      rules2 = jurisdiction_rules_with(legislation_rules: {retrieval: "legistar"})
      expect(rules2.generic_portal_urls).to eq([])
    end
  end

  describe "evidence attribution properties in roster_rules" do
    it "exposes evidence_publisher, evidence_jurisdiction, and evidence_source_url helper readers" do
      rules = jurisdiction_rules_with(
        roster_rules: {
          retrieval: "open_states",
          parsing: "open_states",
          evidence_publisher: "openstates.org",
          evidence_jurisdiction: "maryland-maryland-united_states",
          evidence_source_url: "https://v3.openstates.org/people"
        }
      )
      expect(rules.evidence_publisher).to eq("openstates.org")
      expect(rules.evidence_jurisdiction).to eq("maryland-maryland-united_states")
      expect(rules.evidence_source_url).to eq("https://v3.openstates.org/people")
    end

    it "exposes evidence attribution properties via dot notation and hash index on roster_rules" do
      rules = jurisdiction_rules_with(
        roster_rules: {
          retrieval: "curated",
          parsing: "curated",
          evidence_publisher: "baltimorecity.gov",
          evidence_jurisdiction: "baltimore_city",
          evidence_source_url: "https://baltimorecity.gov"
        }
      )
      roster = rules.roster_rules
      if roster
        expect(roster.evidence_publisher).to eq("baltimorecity.gov")
        expect(roster.evidence_jurisdiction).to eq("baltimore_city")
        expect(roster.evidence_source_url).to eq("https://baltimorecity.gov")
        expect(roster[:evidence_publisher]).to eq("baltimorecity.gov")
        expect(roster["evidence_publisher"]).to eq("baltimorecity.gov")
      else
        raise "expected roster_rules"
      end
    end

    it "returns nil when roster_rules is nil or attributes are omitted" do
      rules = jurisdiction_rules_with(roster_rules: nil)
      expect(rules.evidence_publisher).to be_nil
      expect(rules.evidence_jurisdiction).to be_nil
      expect(rules.evidence_source_url).to be_nil

      rules_omitted = jurisdiction_rules_with(roster_rules: {retrieval: "curated", parsing: "curated"})
      expect(rules_omitted.evidence_publisher).to be_nil
      expect(rules_omitted.evidence_jurisdiction).to be_nil
      expect(rules_omitted.evidence_source_url).to be_nil
    end
  end

  describe "vote_rules historical fallback toggle and timezone configuration" do
    it "exposes enable_historical_fallback? and vote_timezone helper readers" do
      rules = jurisdiction_rules_with(
        vote_rules: {
          retrieval: "maryland_general_assembly",
          parsing: "generic_html",
          enable_historical_fallback: true,
          timezone: "America/New_York"
        }
      )
      expect(rules.enable_historical_fallback?).to be(true)
      expect(rules.enable_historical_fallback).to be(true)
      expect(rules.vote_timezone).to eq("America/New_York")
    end

    it "exposes enable_historical_fallback and timezone via dot notation and hash index on vote_rules" do
      rules = jurisdiction_rules_with(
        vote_rules: {
          retrieval: "congress_dot_gov",
          parsing: "congress_dot_gov",
          enable_historical_fallback: false,
          timezone: "America/New_York"
        }
      )
      vote = rules.vote_rules
      if vote
        expect(vote.enable_historical_fallback).to be(false)
        expect(vote.timezone).to eq("America/New_York")
        expect(vote[:enable_historical_fallback]).to be(false)
        expect(vote["enable_historical_fallback"]).to be(false)
        expect(vote[:timezone]).to eq("America/New_York")
        expect(vote["timezone"]).to eq("America/New_York")
      else
        raise "expected vote_rules"
      end
    end

    it "defaults enable_historical_fallback? to false and vote_timezone to nil when omitted or vote_rules is nil" do
      rules = jurisdiction_rules_with(vote_rules: nil)
      expect(rules.enable_historical_fallback?).to be(false)
      expect(rules.enable_historical_fallback).to be(false)
      expect(rules.vote_timezone).to be_nil

      rules_omitted = jurisdiction_rules_with(vote_rules: {retrieval: "manual", parsing: "manual"})
      expect(rules_omitted.enable_historical_fallback?).to be(false)
      expect(rules_omitted.enable_historical_fallback).to be(false)
      expect(rules_omitted.vote_timezone).to be_nil
    end
  end

  describe "declarative configuration in active YAML files" do
    it "loads expected evidence attribution and vote rules for Baltimore" do
      doc = SwayLocale::DocumentReader.read(File.join(SwayLocale::DocumentReader.default_directory, "baltimore-maryland-united_states.yml"))
      rules = doc.to_jurisdiction_rules

      expect(rules.evidence_publisher).to eq("baltimorecity.gov")
      expect(rules.evidence_jurisdiction).to eq("baltimore_city")
      expect(rules.evidence_source_url).to eq("https://baltimorecity.gov")
      expect(rules.enable_historical_fallback?).to be(false)
      expect(rules.vote_timezone).to eq("America/New_York")
    end

    it "loads expected evidence attribution and vote rules for Maryland" do
      doc = SwayLocale::DocumentReader.read(File.join(SwayLocale::DocumentReader.default_directory, "maryland-maryland-united_states.yml"))
      rules = doc.to_jurisdiction_rules

      expect(rules.evidence_publisher).to eq("openstates.org")
      expect(rules.evidence_jurisdiction).to eq("maryland-maryland-united_states")
      expect(rules.evidence_source_url).to eq("https://v3.openstates.org/people")
      expect(rules.enable_historical_fallback?).to be(true)
      expect(rules.vote_timezone).to eq("America/New_York")
    end

    it "loads expected evidence attribution and vote rules for Congress" do
      doc = SwayLocale::DocumentReader.read(File.join(SwayLocale::DocumentReader.default_directory, "congress-congress-united_states.yml"))
      rules = doc.to_jurisdiction_rules

      expect(rules.evidence_publisher).to eq("congress.gov")
      expect(rules.evidence_jurisdiction).to eq("us_congress")
      expect(rules.evidence_source_url).to eq("https://api.congress.gov/v3/member")
      expect(rules.enable_historical_fallback?).to be(false)
      expect(rules.vote_timezone).to eq("America/New_York")
    end

    it "loads expected evidence attribution and vote rules for Annapolis" do
      doc = SwayLocale::DocumentReader.read(File.join(SwayLocale::DocumentReader.default_directory, "annapolis-maryland-united_states.yml"))
      rules = doc.to_jurisdiction_rules

      expect(rules.evidence_publisher).to eq("annapolis.gov")
      expect(rules.evidence_jurisdiction).to eq("annapolis_city")
      expect(rules.evidence_source_url).to eq("https://www.annapolis.gov/483/City-Council")
      expect(rules.enable_historical_fallback?).to be(false)
      expect(rules.vote_timezone).to eq("America/New_York")
    end
  end
end
