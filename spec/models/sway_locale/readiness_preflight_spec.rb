# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe SwayLocale::ReadinessPreflight do
  describe ".check_all" do
    it "evaluates all built-in sway locales as ready without error" do
      results = described_class.check_all

      expect(results.size).to be >= 3
      expect(results.map(&:ready?)).to all(be(true))
      expect(results.map(&:errors)).to all(be_empty)

      names = results.map(&:sway_locale_name)
      expect(names).to include("baltimore-maryland-united_states")
      expect(names).to include("congress-congress-united_states")
      expect(names).to include("maryland-maryland-united_states")
    end

    it "inspects capabilities correctly for built-in Baltimore" do
      result = described_class.check_file(
        Rails.root.join("config", "sway_locales", "baltimore-maryland-united_states.yml").to_s
      )

      expect(result.ready?).to be(true)
      expect(result.capabilities[:roster]).to eq(:automatic)
      expect(result.capabilities[:votes]).to eq(:manual)
      expect(result.capabilities[:law]).to eq(:automatic)
      expect(result.roster_bootstrap_present).to be(true)
      expect(result.geography_present).to be(true)
      expect(result.icon_present).to be(true)
      expect(result.icon_path).to eq("public/images/flags/baltimore-maryland-united_states.svg")
    end

    it "ignores example files (*.example.yml) and underscore files in check_all" do
      results = described_class.check_all
      expect(results.map(&:filename)).not_to include("locale.example.yml")
    end
  end

  describe ".check_file" do
    let(:tmp_dir) { Dir.mktmpdir("sway_locale_preflight_spec") }

    after do
      FileUtils.remove_entry(tmp_dir) if File.exist?(tmp_dir)
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Maryland PDF law corpus acquisition#Readiness accepts the configured retrieval and parser]]
    it "accepts Maryland's configured PDF catalog retrieval and statute section parser" do
      result = described_class.check_file(
        Rails.root.join("config", "sway_locales", "maryland-maryland-united_states.yml").to_s
      )

      expect(result.ready?).to be(true), result.errors.join("; ")
      expect(result.capabilities[:law]).to eq(:automatic)
      expect(result.capabilities[:law_retrieval]).to eq("configured_pdf_catalog")
      expect(result.capabilities[:law_parsing]).to eq("pdf_statute_sections")
    end

    it "rejects law identifiers assigned to the wrong capability role" do
      law_rules = [
        {retrieval: "configured_pdf_catalog", parsing: "unknown_parser"},
        {retrieval: "pdf_statute_sections", parsing: "generic_xml"}
      ]

      law_rules.each do |rules|
        doc = Struct.new(:name, :source_rules, :roster_rules, :vote_rules, :law_rules).new(
          "maryland-maryland-united_states",
          {publishes_legislator_votes: false},
          {retrieval: "curated", parsing: "curated", curated_readiness_check: true},
          {retrieval: "manual", parsing: "manual"},
          rules
        )
        result = described_class::Result.new(file_path: "maryland.yml")

        described_class.send(:check_capabilities, doc, result)

        unsupported_value = (rules[:retrieval] == "configured_pdf_catalog") ? "unknown_parser" : "pdf_statute_sections"
        expect(result.capabilities[:law]).to eq(:unsupported), rules.inspect
        expect(result.errors).to include("SwayLocale maryland-maryland-united_states declared unsupported law engine: #{unsupported_value.inspect}")
      end
    end

    it "reports useful filename and error messages for a malformed schema" do
      bad_yaml = <<~YAML
        schema_version: 1
        city: "malformed"
        region: "maryland"
        country: "united_states"
        name: "malformed-maryland-united_states"
        unknown_field: "disallowed"
      YAML
      file_path = File.join(tmp_dir, "malformed-maryland-united_states.yml")
      File.write(file_path, bad_yaml)

      result = described_class.check_file(file_path)

      expect(result.ready?).to be(false)
      expect(result.filename).to eq("malformed-maryland-united_states.yml")
      expect(result.errors.first).to include("malformed-maryland-united_states.yml")
      expect(result.errors.first).to include("Unknown schema field")
    end

    it "reports syntax error in filename without crashing" do
      bad_yaml = "city: [unclosed list"
      file_path = File.join(tmp_dir, "broken.yml")
      File.write(file_path, bad_yaml)

      result = described_class.check_file(file_path)

      expect(result.ready?).to be(false)
      expect(result.filename).to eq("broken.yml")
      expect(result.errors.first).to include("Malformed YAML")
    end

    it "identifies and reports a manual-only locale as manual-only" do
      manual_yaml = <<~YAML
        schema_version: 1
        city: "annapolis"
        region: "maryland"
        region_code: "MD"
        country: "united_states"
        name: "annapolis-maryland-united_states"
        time_zone: "America/New_York"
        icon_url: "https://example.com/icon.png"
        sample_address:
          street: "160 Duke of Gloucester St"
          postal_code: "21401"
          latitude: 38.9784
          longitude: -76.4922
        source_rules:
          publishes_legislator_votes: false
          chamber_label: "City Council"
          session_numbering: "term_years"
          default_bill_chamber: "council"
          bill_chambers:
            - "council"
          roster_rules:
            retrieval: "curated"
            parsing: "curated"
          vote_rules:
            retrieval: "manual"
            parsing: "manual"
          law_rules:
            retrieval: "unavailable"
            parsing: "unavailable"
        term_rules:
          convening:
            kind: "fixed_day"
            month: 1
            day: 1
          cycle_anchor_year: 2025
          cycle_years: 4
          roster_lists_only_current_legislators: true
          publishes_term_history: false
          publishes_exact_term_dates: false
          identified_by: "person"
        news_sources: []
      YAML
      file_path = File.join(tmp_dir, "annapolis-maryland-united_states.yml")
      File.write(file_path, manual_yaml)

      result = described_class.check_file(file_path)

      expect(result.capabilities[:roster]).to eq(:manual_curation)
      expect(result.capabilities[:votes]).to eq(:manual)
      expect(result.capabilities[:law]).to eq(:unavailable)
      expect(result.manual_only?).to be(true)
    end

    it "refuses to report ready when OpenStates votes are declared for non-Maryland states" do
      virginia_yaml = <<~YAML
        schema_version: 1
        city: "virginia"
        region: "virginia"
        region_code: "VA"
        country: "united_states"
        name: "virginia-virginia-united_states"
        time_zone: "America/New_York"
        icon_url: "https://example.com/icon.png"
        source_rules:
          publishes_legislator_votes: true
          chamber_label: "General Assembly"
          session_numbering: "term_years"
          default_bill_chamber: "house"
          bill_chambers:
            - "house"
            - "senate"
          roster_rules:
            retrieval: "open_states"
            parsing: "open_states"
            jurisdiction: "Virginia"
          vote_rules:
            retrieval: "open_states"
            parsing: "open_states"
            jurisdiction: "Virginia"
          law_rules:
            retrieval: "unavailable"
            parsing: "unavailable"
        term_rules:
          convening:
            kind: "fixed_day"
            month: 1
            day: 1
          cycle_anchor_year: 2024
          cycle_years: 2
          roster_lists_only_current_legislators: true
          publishes_term_history: false
          publishes_exact_term_dates: false
          identified_by: "person"
        news_sources: []
      YAML
      file_path = File.join(tmp_dir, "virginia-virginia-united_states.yml")
      File.write(file_path, virginia_yaml)

      result = described_class.check_file(file_path)

      expect(result.ready?).to be(false)
      expect(result.capabilities[:votes]).to eq(:unsupported)
      expect(result.errors.any? { |e| e.include?("OpenStates votes scraper only supports Maryland (MD), not VA") }).to be(true)
    end

    it "flags missing geography polygon for a municipal locale" do
      city_yaml = <<~YAML
        schema_version: 1
        city: "bethesda"
        region: "maryland"
        region_code: "MD"
        country: "united_states"
        name: "bethesda-maryland-united_states"
        time_zone: "America/New_York"
        icon_url: "https://example.com/icon.png"
        source_rules:
          publishes_legislator_votes: false
          chamber_label: "Town Council"
          session_numbering: "term_years"
          default_bill_chamber: "council"
          bill_chambers:
            - "council"
          roster_rules:
            retrieval: "curated"
            parsing: "curated"
          vote_rules:
            retrieval: "manual"
            parsing: "manual"
          law_rules:
            retrieval: "unavailable"
            parsing: "unavailable"
        term_rules:
          convening:
            kind: "fixed_day"
            month: 1
            day: 1
          cycle_anchor_year: 2025
          cycle_years: 4
          roster_lists_only_current_legislators: true
          publishes_term_history: false
          publishes_exact_term_dates: false
          identified_by: "person"
        news_sources: []
      YAML
      file_path = File.join(tmp_dir, "bethesda-maryland-united_states.yml")
      File.write(file_path, city_yaml)

      result = described_class.check_file(file_path)

      expect(result.geography_present).to be(false)
      expect(result.errors.any? { |e| e.include?("missing required geography polygon") }).to be(true)
    end

    it "evaluates capabilities using explicit retrieval and parsing without legacy engine" do
      explicit_yaml = <<~YAML
        schema_version: 1
        city: "congress"
        region: "congress"
        region_code: "US"
        country: "united_states"
        name: "congress-congress-united_states"
        time_zone: "America/New_York"
        icon_url: "https://example.com/icon.png"
        source_rules:
          publishes_legislator_votes: true
          chamber_label: "Congress"
          session_numbering: "congress_ordinal"
          default_bill_chamber: "house"
          bill_chambers:
            - "house"
            - "senate"
          legislation_rules:
            retrieval: "generic_rest"
            parsing: "generic_json"
            base_url: "https://api.congress.gov/v3"
          hearings_rules:
            retrieval: "generic_rest"
            parsing: "generic_json"
            base_url: "https://api.congress.gov/v3"
          roster_rules:
            retrieval: "congress_dot_gov"
            parsing: "congress_dot_gov"
            base_url: "https://unitedstates.github.io/congress-legislators"
          vote_rules:
            retrieval: "congress_dot_gov"
            parsing: "congress_dot_gov"
            base_url: "https://api.congress.gov/v3"
          law_rules:
            retrieval: "generic_rest"
            parsing: "uslm_xml"
            base_url: "https://uscode.house.gov"
        term_rules:
          convening:
            kind: "fixed_day"
            month: 1
            day: 3
          cycle_anchor_year: 1991
          cycle_years: 2
          roster_lists_only_current_legislators: false
          publishes_term_history: true
          publishes_exact_term_dates: true
          identified_by: "person"
        news_sources: []
      YAML
      file_path = File.join(tmp_dir, "congress-congress-united_states.yml")
      File.write(file_path, explicit_yaml)

      result = described_class.check_file(file_path)

      expect(result.ready?).to be(true)
      expect(result.capabilities[:roster]).to eq(:automatic)
      expect(result.capabilities[:votes]).to eq(:automatic)
      expect(result.capabilities[:law]).to eq(:automatic)
      expect(result.capabilities[:roster_detail]).to include("congress_dot_gov")
      expect(result.capabilities[:votes_detail]).to include("congress_dot_gov")
      expect(result.capabilities[:law_detail]).to include("generic_rest")
    end

    it "identifies manual-only locale when explicit retrieval and parsing declare unavailable or manual" do
      manual_explicit_yaml = <<~YAML
        schema_version: 1
        city: "annapolis"
        region: "maryland"
        region_code: "MD"
        country: "united_states"
        name: "annapolis-maryland-united_states"
        time_zone: "America/New_York"
        icon_url: "https://example.com/icon.png"
        sample_address:
          street: "160 Duke of Gloucester St"
          postal_code: "21401"
          latitude: 38.9784
          longitude: -76.4922
        source_rules:
          publishes_legislator_votes: false
          chamber_label: "City Council"
          session_numbering: "term_years"
          default_bill_chamber: "council"
          bill_chambers:
            - "council"
          roster_rules:
            retrieval: "curated"
            parsing: "curated"
          vote_rules:
            retrieval: "manual"
            parsing: "manual"
          law_rules:
            retrieval: "unavailable"
            parsing: "unavailable"
        term_rules:
          convening:
            kind: "fixed_day"
            month: 1
            day: 1
          cycle_anchor_year: 2025
          cycle_years: 4
          roster_lists_only_current_legislators: true
          publishes_term_history: false
          publishes_exact_term_dates: false
          identified_by: "person"
        news_sources: []
      YAML
      file_path = File.join(tmp_dir, "annapolis-maryland-united_states.yml")
      File.write(file_path, manual_explicit_yaml)

      result = described_class.check_file(file_path)

      expect(result.capabilities[:roster]).to eq(:manual_curation)
      expect(result.capabilities[:votes]).to eq(:manual)
      expect(result.capabilities[:law]).to eq(:unavailable)
      expect(result.manual_only?).to be(true)
    end

    it "flags unsupported retrieval or parsing formats during preflight" do
      invalid_yaml = <<~YAML
        schema_version: 1
        city: "congress"
        region: "congress"
        region_code: "US"
        country: "united_states"
        name: "congress-congress-united_states"
        time_zone: "America/New_York"
        icon_url: "https://example.com/icon.png"
        source_rules:
          publishes_legislator_votes: true
          chamber_label: "Congress"
          session_numbering: "congress_ordinal"
          default_bill_chamber: "house"
          bill_chambers:
            - "house"
            - "senate"
          roster_rules:
            retrieval: "unsupported_roster_proto"
            parsing: "unsupported_roster_format"
          vote_rules:
            retrieval: "unsupported_vote_proto"
            parsing: "unsupported_vote_format"
          law_rules:
            retrieval: "unsupported_law_proto"
            parsing: "unsupported_law_format"
        term_rules:
          convening:
            kind: "fixed_day"
            month: 1
            day: 3
          cycle_anchor_year: 1991
          cycle_years: 2
          roster_lists_only_current_legislators: false
          publishes_term_history: true
          publishes_exact_term_dates: true
          identified_by: "person"
        news_sources: []
      YAML
      file_path = File.join(tmp_dir, "congress-congress-united_states.yml")
      File.write(file_path, invalid_yaml)

      result = described_class.check_file(file_path)

      expect(result.ready?).to be(false)
      expect(result.capabilities[:roster]).to eq(:unsupported)
      expect(result.capabilities[:votes]).to eq(:unsupported)
      expect(result.capabilities[:law]).to eq(:unsupported)
      expect(result.errors.any? { |e| e.include?("unsupported roster engine") }).to be(true)
      expect(result.errors.any? { |e| e.include?("unsupported vote engine") }).to be(true)
      expect(result.errors.any? { |e| e.include?("unsupported law engine") }).to be(true)
    end

    it "evaluates curated roster without curated_readiness_check as :manual_curation even if city is baltimore" do
      yaml = <<~YAML
        schema_version: 1
        city: "baltimore"
        region: "maryland"
        region_code: "MD"
        country: "united_states"
        name: "baltimore-maryland-united_states"
        time_zone: "America/New_York"
        icon_url: "https://example.com/icon.png"
        sample_address:
          street: "100 N Holliday St"
          postal_code: "21202"
          latitude: 39.2904
          longitude: -76.6122
        source_rules:
          publishes_legislator_votes: false
          chamber_label: "City Council"
          session_numbering: "term_years"
          default_bill_chamber: "council"
          bill_chambers:
            - "council"
          roster_rules:
            retrieval: "curated"
            parsing: "curated"
          vote_rules:
            retrieval: "manual"
            parsing: "manual"
          law_rules:
            retrieval: "unavailable"
            parsing: "unavailable"
        term_rules:
          convening:
            kind: "fixed_day"
            month: 1
            day: 1
          cycle_anchor_year: 2025
          cycle_years: 4
          roster_lists_only_current_legislators: true
          publishes_term_history: false
          publishes_exact_term_dates: false
          identified_by: "person"
        news_sources: []
      YAML
      sub_dir = File.join(tmp_dir, "manual_baltimore")
      FileUtils.mkdir_p(sub_dir)
      file_path = File.join(sub_dir, "baltimore-maryland-united_states.yml")
      File.write(file_path, yaml)

      result = described_class.check_file(file_path)

      expect(result.capabilities[:roster]).to eq(:manual_curation)
      expect(result.capabilities[:roster_detail]).to eq("Automatic roster refresh is unavailable (manual curation)")
    end

    it "evaluates curated roster with curated_readiness_check: true as :automatic via curated" do
      yaml = <<~YAML
        schema_version: 1
        city: "baltimore"
        region: "maryland"
        region_code: "MD"
        country: "united_states"
        name: "baltimore-maryland-united_states"
        time_zone: "America/New_York"
        icon_url: "https://example.com/icon.png"
        sample_address:
          street: "100 N Holliday St"
          postal_code: "21202"
          latitude: 39.2904
          longitude: -76.6122
        source_rules:
          publishes_legislator_votes: false
          chamber_label: "City Council"
          session_numbering: "term_years"
          default_bill_chamber: "council"
          bill_chambers:
            - "council"
          roster_rules:
            retrieval: "curated"
            parsing: "curated"
            curated_readiness_check: true
          vote_rules:
            retrieval: "manual"
            parsing: "manual"
          law_rules:
            retrieval: "unavailable"
            parsing: "unavailable"
        term_rules:
          convening:
            kind: "fixed_day"
            month: 1
            day: 1
          cycle_anchor_year: 2025
          cycle_years: 4
          roster_lists_only_current_legislators: true
          publishes_term_history: false
          publishes_exact_term_dates: false
          identified_by: "person"
        news_sources: []
      YAML
      sub_dir = File.join(tmp_dir, "curated_check_baltimore")
      FileUtils.mkdir_p(sub_dir)
      file_path = File.join(sub_dir, "baltimore-maryland-united_states.yml")
      File.write(file_path, yaml)

      result = described_class.check_file(file_path)

      expect(result.capabilities[:roster]).to eq(:automatic)
      expect(result.capabilities[:roster_detail]).to eq("Automatic roster refresh via curated")
    end

    it "evaluates legacy baltimore roster engine as unsupported" do
      yaml = <<~YAML
        schema_version: 1
        city: "baltimore"
        region: "maryland"
        region_code: "MD"
        country: "united_states"
        name: "baltimore-maryland-united_states"
        time_zone: "America/New_York"
        icon_url: "https://example.com/icon.png"
        sample_address:
          street: "100 N Holliday St"
          postal_code: "21202"
          latitude: 39.2904
          longitude: -76.6122
        source_rules:
          publishes_legislator_votes: false
          chamber_label: "City Council"
          session_numbering: "term_years"
          default_bill_chamber: "council"
          bill_chambers:
            - "council"
          roster_rules:
            retrieval: "baltimore"
            parsing: "baltimore"
          vote_rules:
            retrieval: "manual"
            parsing: "manual"
          law_rules:
            retrieval: "unavailable"
            parsing: "unavailable"
        term_rules:
          convening:
            kind: "fixed_day"
            month: 1
            day: 1
          cycle_anchor_year: 2025
          cycle_years: 4
          roster_lists_only_current_legislators: true
          publishes_term_history: false
          publishes_exact_term_dates: false
          identified_by: "person"
        news_sources: []
      YAML
      sub_dir = File.join(tmp_dir, "unsupported_baltimore")
      FileUtils.mkdir_p(sub_dir)
      file_path = File.join(sub_dir, "baltimore-maryland-united_states.yml")
      File.write(file_path, yaml)

      result = described_class.check_file(file_path)

      expect(result.capabilities[:roster]).to eq(:unsupported)
      expect(result.errors.any? { |e| e.include?("unsupported roster engine: \"baltimore\"") }).to be(true)
      expect(result.ready?).to be(false)
    end

    # @lat: [[lat.md/explanation/jurisdiction-rules.md#Readiness Preflight Decoupling]]
    it "validates decoupled retrieval and parsing capabilities independently and strictly requires boolean true for curated_readiness_check" do
      base_yaml = YAML.safe_load_file(
        SwayLocale::DocumentReader.default_directory.join("baltimore-maryland-united_states.yml"),
        permitted_classes: [Date, Time]
      )
      p1 = File.join(tmp_dir, "baltimore-maryland-united_states.yml")

      ["true", 1, [true], {"check" => true}, false, nil].each do |non_true_val|
        curated_yaml = Marshal.load(Marshal.dump(base_yaml))
        curated_yaml["source_rules"]["roster_rules"] = {
          "retrieval" => "curated",
          "parsing" => "curated",
          "curated_readiness_check" => non_true_val
        }
        File.write(p1, YAML.dump(curated_yaml))
        res_curated = described_class.check_file(p1)
        expect(res_curated.capabilities[:roster]).to eq(:manual_curation)
      end

      auto_yaml = Marshal.load(Marshal.dump(base_yaml))
      auto_yaml["source_rules"]["roster_rules"] = {
        "retrieval" => "curated",
        "parsing" => "curated",
        "curated_readiness_check" => true
      }
      File.write(p1, YAML.dump(auto_yaml))
      res_auto = described_class.check_file(p1)
      expect(res_auto.capabilities[:roster]).to eq(:automatic)
    end
  end
end
