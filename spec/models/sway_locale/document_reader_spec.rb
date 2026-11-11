# frozen_string_literal: true

require "rails_helper"

RSpec.describe SwayLocale::DocumentReader do
  describe ".discover" do
    it "discovers all YAML files sorted deterministically by filename" do
      docs = described_class.discover
      expected = described_class.discover_paths.map { |f| File.basename(f, ".yml") }.sort
      expect(docs.map(&:name)).to eq(expected)
    end

    it "produces identical results regardless of filesystem directory iteration order" do
      files = described_class.discover_paths.sort
      allow(Dir).to receive(:glob).and_return(files.reverse)

      docs = described_class.discover
      expect(docs.map(&:name)).to eq(files.map { |f| File.basename(f, ".yml") })
    end

    it "filters example and template YAML files from discover_paths" do
      paths = described_class.discover_paths
      expect(paths.none? { |p| File.basename(p).end_with?(".example.yml") || File.basename(p).start_with?("_") }).to be(true)
    end

    it "discovers a fourth added file without editing any shared registry or list" do
      Dir.mktmpdir do |dir|
        # Copy existing files
        FileUtils.cp_r(Dir.glob(File.join(described_class.default_directory, "*.yml")), dir)

        # Add a 4th file
        fourth_yaml = <<~YAML
          schema_version: 1
          city: annapolis
          region: maryland
          region_code: MD
          country: united_states
          name: annapolis-maryland-united_states
          legislative_sessions:
            - name: "2025-2029 City Council"
              start_date: "2025-01-01"
              end_date: "2029-01-01"
              active: true
              upstream_name: "2025-2029 City Council"
          time_zone: America/New_York
          icon_url: logo.svg
          source_rules:
            publishes_legislator_votes: false
            chamber_label: City Council
            session_numbering: term_years
            default_bill_chamber: council
            bill_chambers:
              - council
            roster_rules:
              retrieval: curated
              parsing: curated
            vote_rules:
              retrieval: manual
              parsing: manual
            legislation_rules:
              retrieval: legistar
              parsing: legistar
              base_url: "https://webapi.legistar.com/v1"
            law_rules:
              retrieval: unavailable
              parsing: unavailable
          term_rules:
            convening:
              kind: fixed_day
              month: 12
              day: 1
            cycle_anchor_year: 2025
            cycle_years: 4
            roster_lists_only_current_legislators: true
            publishes_term_history: false
            publishes_exact_term_dates: false
            identified_by: seat
          news_sources: []
        YAML
        File.write(File.join(dir, "annapolis-maryland-united_states.yml"), fourth_yaml)

        discovered = described_class.discover(dir)
        expect(discovered.map(&:name)).to eq([
          "annapolis-maryland-united_states",
          "baltimore-maryland-united_states",
          "congress-congress-united_states",
          "maryland-maryland-united_states"
        ])
      end
    end

    it "rejects duplicate normalized identities across discovered files" do
      Dir.mktmpdir do |dir|
        # Mock read to return two documents with identical name from two different files
        allow(described_class).to receive(:read).and_return(
          described_class::Document.new(
            YAML.safe_load_file(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml")),
            filename: "file1.yml"
          ),
          described_class::Document.new(
            YAML.safe_load_file(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml")),
            filename: "file2.yml"
          )
        )
        allow(Dir).to receive(:glob).and_return(["file1.yml", "file2.yml"])

        expect {
          described_class.discover(dir)
        }.to raise_error(described_class::DuplicateIdentityError, /Duplicate SwayLocale identity/)
      end
    end

    it "does not re-read YAML files on repeated .all and .find calls when files are unchanged" do
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir.glob(File.join(described_class.default_directory, "*.yml")), dir)

        initial = described_class.all(dir)
        expect(initial).not_to be_empty

        expect(File).not_to receive(:read)

        expect(described_class.all(dir)).to eq(initial)
        expect(described_class.find("baltimore-maryland-united_states", dir)&.name)
          .to eq("baltimore-maryland-united_states")
      end
    end

    it "bypasses cache when .read is stubbed after a warm .all call and does not poison @discover_cache" do
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir.glob(File.join(described_class.default_directory, "*.yml")), dir)

        initial = described_class.all(dir)
        expect(initial).not_to be_empty

        stub_docs = initial.each_with_index.map do |doc, idx|
          described_class::Document.new(
            doc.data.merge("name" => "stubbed-#{idx}-maryland-united_states"),
            filename: doc.filename
          )
        end

        allow(described_class).to receive(:read).and_return(*stub_docs)
        expect(described_class.all(dir)).to eq(stub_docs)

        mocks = RSpec::Mocks #: untyped
        mocks.space.proxy_for(described_class).reset
        expect(File).not_to receive(:read)
        expect(described_class.all(dir)).to eq(initial)
      end
    end
  end

  describe ".read" do
    it "correctly parses the built-in Baltimore document" do
      doc = described_class.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))

      expect(doc.city).to eq("baltimore")
      expect(doc.region).to eq("maryland")
      expect(doc.region_code).to eq("MD")
      expect(doc.country).to eq("united_states")
      expect(doc.name).to eq("baltimore-maryland-united_states")
      expect(doc.legislative_sessions.find(&:active).start_date).to eq(Date.parse("2024-12-05"))
      expect(doc.time_zone).to eq("America/New_York")
      expect(doc.sample_street).to eq("100 N Holliday St")
      expect(doc.sample_postal_code).to eq("21202")
      expect(doc.sample_latitude).to eq(39.29105)
      expect(doc.sample_longitude).to eq(-76.61069)
      expect(doc.source_rules[:publishes_legislator_votes]).to be(false)
      expect(doc.source_rules[:chamber_label]).to eq("City Council")
      expect(doc.source_rules[:default_bill_chamber]).to eq("council")
      expect(doc.term_rules[:cycle_anchor_year]).to eq(2024)
      expect(doc.term_rules[:cycle_years]).to eq(4)
      expect(doc.term_rules[:identified_by]).to eq("seat")
      expect(doc.term_rules[:seat_chambers]).to eq({
        "Mayor" => "Executive",
        "Council President" => "City Council",
        "Council Member" => "City Council"
      })
    end

    it "instantiates equivalent JurisdictionRules and TermRules for Baltimore" do
      doc = described_class.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))

      j_rules = doc.to_jurisdiction_rules
      expect(j_rules.respond_to?(:roster_source)).to be(false)
      expect(j_rules.respond_to?(:vote_source)).to be(false)
      expect(j_rules.respond_to?(:legistar_client)).to be(false)
      expect(j_rules.respond_to?(:roster_refresher)).to be(false)
      expect(j_rules.publishes_legislator_votes).to be(false)
      expect(j_rules.chamber_label).to eq("City Council")
      expect(j_rules.default_bill_chamber).to eq("council")
      expect(j_rules.bill_chambers).to eq(%w[council])
      expect(j_rules.vote_retrieval).to eq("legistar")
      expect(j_rules.vote_parsing).to eq("legistar")
      expect(j_rules.legislation_retrieval).to eq("legistar")
      expect(j_rules.legislation_parsing).to eq("legistar")

      t_rules = doc.to_term_rules
      expect(t_rules.cycle_anchor_year).to eq(2024)
      expect(t_rules.cycle_years).to eq(4)
      expect(t_rules.roster_lists_only_current_legislators).to be(true)
      expect(t_rules.identified_by).to eq(:seat)
      expect(t_rules.seat_chambers).to eq({
        "Mayor" => "Executive",
        "Council President" => "City Council",
        "Council Member" => "City Council"
      })
      expect(t_rules.convening).to be_a(SwayLocale::NthWeekdayConvening)
    end

    # @lat: [[seed-legislator-title-tests#Configured roster seat mapping#Allows configured seat chambers on person-keyed rosters]]
    it "accepts seat chamber mappings for a person-keyed roster" do
      Dir.mktmpdir do |dir|
        yaml = <<~YAML
          schema_version: 1
          city: synthetic
          region: maryland
          country: united_states
          name: synthetic-maryland-united_states
          time_zone: America/New_York
          source_rules:
            publishes_legislator_votes: false
            chamber_label: Synthetic Council
            session_numbering: term_years
            default_bill_chamber: council
            bill_chambers: [council]
          term_rules:
            convening:
              kind: fixed_day
              month: 1
              day: 1
            cycle_anchor_year: 2025
            cycle_years: 4
            roster_lists_only_current_legislators: true
            publishes_term_history: false
            publishes_exact_term_dates: false
            identified_by: person
            seat_chambers:
              Representative: Synthetic Council
          news_sources: []
        YAML
        file = File.join(dir, "synthetic-maryland-united_states.yml")
        File.write(file, yaml)

        doc = described_class.read(file)
        expect(doc.to_term_rules.seat_chambers).to eq({"Representative" => "Synthetic Council"})
        expect(doc.term_rules[:seat_chambers]).to eq({"Representative" => "Synthetic Council"})
      end
    end

    it "rejects an empty seat chamber mapping instead of silently opting in" do
      Dir.mktmpdir do |dir|
        yaml = <<~YAML
          schema_version: 1
          city: synthetic
          region: maryland
          country: united_states
          name: synthetic-maryland-united_states
          time_zone: America/New_York
          source_rules:
            publishes_legislator_votes: false
            chamber_label: Synthetic Council
            session_numbering: term_years
            default_bill_chamber: council
            bill_chambers: [council]
          term_rules:
            convening:
              kind: fixed_day
              month: 1
              day: 1
            cycle_anchor_year: 2025
            cycle_years: 4
            roster_lists_only_current_legislators: true
            publishes_term_history: false
            publishes_exact_term_dates: false
            identified_by: seat
            seat_chambers: {}
          news_sources: []
        YAML
        file = File.join(dir, "synthetic-maryland-united_states.yml")
        File.write(file, yaml)

        expect { described_class.read(file) }
          .to raise_error(described_class::ValidationError, /seat_chambers must declare at least one title/)
      end
    end

    it "instantiates equivalent JurisdictionRules and TermRules for Congress" do
      doc = described_class.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))

      j_rules = doc.to_jurisdiction_rules
      expect(j_rules.respond_to?(:roster_source)).to be(false)
      expect(j_rules.respond_to?(:vote_source)).to be(false)
      expect(j_rules.chamber_label).to eq("Congress")
      expect(j_rules.vote_retrieval).to eq("congress_dot_gov")
      expect(j_rules.vote_parsing).to eq("congress_dot_gov")
      expect(j_rules.roster_retrieval).to eq("congress_dot_gov")
      expect(j_rules.roster_parsing).to eq("congress_dot_gov")

      t_rules = doc.to_term_rules
      expect(t_rules.cycle_anchor_year).to eq(1991)
      expect(t_rules.cycle_years).to eq(2)
      expect(t_rules.seat_chambers).to eq({
        "Sen." => "Senate",
        "Rep." => "House of Representatives"
      })
      expect(t_rules.convening).to be_a(SwayLocale::FixedDayConvening)
    end

    it "instantiates equivalent JurisdictionRules and TermRules for Maryland with seat_chambers" do
      doc = described_class.read(File.join(described_class.default_directory, "maryland-maryland-united_states.yml"))

      t_rules = doc.to_term_rules
      expect(t_rules.cycle_anchor_year).to eq(2023)
      expect(t_rules.cycle_years).to eq(4)
      expect(t_rules.seat_chambers).to eq({
        "Senator" => "Senate",
        "Delegate" => "House of Delegates",
        "Governor" => "Executive"
      })
    end

    it "rejects malformed YAML syntax" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "bad-syntax.yml")
        File.write(file, "schema_version: 1\n  invalid: indentation:\n")

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Malformed YAML/)
      end
    end

    it "rejects duplicate mapping keys" do
      Dir.mktmpdir do |dir|
        yaml = <<~YAML
          schema_version: 1
          city: baltimore
          region: maryland
          region: duplicate_maryland
          country: united_states
          name: baltimore-maryland-united_states
        YAML
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, yaml)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::DuplicateKeyError, /Duplicate mapping key "region"/)
      end
    end

    it "rejects nested duplicate mapping keys in source_rules" do
      Dir.mktmpdir do |dir|
        yaml = <<~YAML
          schema_version: 1
          city: baltimore
          region: maryland
          country: united_states
          name: baltimore-maryland-united_states
          current_legislative_session_start_date: "2024-12-05"
          time_zone: America/New_York
          source_rules:
            roster_source: curated
            roster_source: curated
        YAML
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, yaml)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::DuplicateKeyError, /Duplicate mapping key "roster_source"/)
      end
    end

    it "rejects filename mismatches with declared name" do
      Dir.mktmpdir do |dir|
        content = File.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
        file = File.join(dir, "wrong-name-slug.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::FilenameMismatchError, /Filename "wrong-name-slug.yml" does not match declared name/)
      end
    end

    it "rejects unknown top-level schema fields" do
      Dir.mktmpdir do |dir|
        content = File.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml")) + "\nunknown_field: true\n"
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Unknown schema field "unknown_field"/)
      end
    end

    it "rejects unknown fields in source_rules" do
      Dir.mktmpdir do |dir|
        content = File.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
        content = content.sub("publishes_legislator_votes: false", "publishes_legislator_votes: false\n    unknown_source_opt: 123")
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Unknown field "unknown_source_opt" in source_rules/)
      end
    end

    it "rejects unsupported object tags" do
      Dir.mktmpdir do |dir|
        content = "schema_version: 1\nname: !ruby/object:Foo {}\n"
        file = File.join(dir, "custom-tag.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Unsupported object tag/)
      end
    end

    it "rejects invalid calendar kind" do
      Dir.mktmpdir do |dir|
        content = File.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
        content = content.sub("kind: nth_weekday", "kind: lunar_calendar")
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /"lunar_calendar" is not permitted/)
      end
    end
  end

  describe "integration configuration schemas" do
    clean_base_yaml = lambda {
      content = File.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
      content = content.sub("vote_source: legistar", "vote_source: legistar\n    legistar_client: baltimore")
      content.sub(/\n\s+legislation_rules:.*?\nterm_rules:/m, "\n\nterm_rules:")
    }

    it "parses valid structured integration rules and propagates to JurisdictionRules" do
      Dir.mktmpdir do |dir|
        extra_rules = <<~YAML
          source_rules:
              legislation_rules:
                  retrieval: generic_rest
                  parsing: generic_rest
                  base_url: "https://mgaleg.maryland.gov"
                  metadata_mapping:
                      external_id: "$.matterId"
                      title: "$.title"
              hearings_rules:
                  retrieval: generic_html
                  parsing: generic_html
                  base_url: "https://mgaleg.maryland.gov/hearings"
              vote_rules:
                  retrieval: generic_csv
                  parsing: generic_csv
                  base_url: "https://mgaleg.maryland.gov/votes"
              roster_rules:
                  retrieval: generic_graphql
                  parsing: generic_graphql
                  base_url: "https://api.congress.gov/roster"
              law_rules:
                  retrieval: generic_rest
                  parsing: generic_rest
                  base_url: "https://mgaleg.maryland.gov/laws"
        YAML
        content = clean_base_yaml.call.sub("source_rules:\n", extra_rules)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        doc = described_class.read(file)
        expect(doc.legislation_rules).to eq({
          retrieval: "generic_rest",
          parsing: "generic_rest",
          base_url: "https://mgaleg.maryland.gov",
          metadata_mapping: {external_id: "$.matterId", title: "$.title"}
        })
        expect(doc.hearings_rules).to eq({
          retrieval: "generic_html",
          parsing: "generic_html",
          base_url: "https://mgaleg.maryland.gov/hearings"
        })
        expect(doc.vote_rules).to eq({
          retrieval: "generic_csv",
          parsing: "generic_csv",
          base_url: "https://mgaleg.maryland.gov/votes"
        })
        expect(doc.roster_rules).to eq({
          retrieval: "generic_graphql",
          parsing: "generic_graphql",
          base_url: "https://api.congress.gov/roster"
        })
        expect(doc.law_rules).to eq({
          retrieval: "generic_rest",
          parsing: "generic_rest",
          base_url: "https://mgaleg.maryland.gov/laws"
        })

        j_rules = doc.to_jurisdiction_rules
        expect(j_rules.legislation_rules).to eq(doc.legislation_rules)
        expect(j_rules.hearings_rules).to eq(doc.hearings_rules)
        expect(j_rules.vote_rules).to eq(doc.vote_rules)
        expect(j_rules.roster_rules).to eq(doc.roster_rules)
        expect(j_rules.law_rules).to eq(doc.law_rules)
      end
    end

    it "maintains backwards compatibility when integration rules are omitted" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, clean_base_yaml.call)

        doc = described_class.read(file)
        expect(doc.legislation_rules).to be_nil
        expect(doc.hearings_rules).to be_nil
        expect(doc.vote_rules).to be_nil
        expect(doc.roster_rules).to be_nil
        expect(doc.law_rules).to be_nil

        j_rules = doc.to_jurisdiction_rules
        expect(j_rules.legislation_rules).to be_nil
        expect(j_rules.respond_to?(:legislation_source)).to be(false)
      end
    end

    it "parses active committed locale YAML files with valid integration rules" do
      baltimore = described_class.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
      expect(baltimore.legislation_rules&.[](:retrieval)).to eq("legistar")
      expect(baltimore.legislation_rules&.[](:parsing)).to eq("legistar")
      expect(baltimore.legislation_rules&.[](:engine)).to be_nil
      expect(baltimore.legislation_rules&.[](:client)).to be_nil
      expect(baltimore.hearings_rules&.[](:retrieval)).to eq("legistar")
      expect(baltimore.hearings_rules&.[](:parsing)).to eq("legistar")
      expect(baltimore.hearings_rules&.[](:engine)).to be_nil
      expect(baltimore.hearings_rules&.[](:client)).to be_nil
      expect(baltimore.vote_rules&.[](:retrieval)).to eq("legistar")
      expect(baltimore.vote_rules&.[](:parsing)).to eq("legistar")
      expect(baltimore.vote_rules&.[](:engine)).to be_nil
      expect(baltimore.vote_rules&.[](:client)).to be_nil
      expect(baltimore.roster_rules&.[](:retrieval)).to eq("curated")
      expect(baltimore.roster_rules&.[](:parsing)).to eq("curated")
      expect(baltimore.roster_rules&.[](:engine)).to be_nil
      expect(baltimore.law_rules&.[](:retrieval)).to eq("akoma_ntoso")
      expect(baltimore.law_rules&.[](:parsing)).to eq("akoma_ntoso")
      expect(baltimore.law_rules&.[](:engine)).to be_nil
      expect(baltimore.law_rules&.[](:repo)).to eq("baltimore-legref/law-xml")
      expect(baltimore.law_rules&.[](:branch)).to eq("main")

      maryland = described_class.read(File.join(described_class.default_directory, "maryland-maryland-united_states.yml"))
      expect(maryland.legislation_rules&.[](:retrieval)).to eq("generic_html")
      expect(maryland.legislation_rules&.[](:parsing)).to eq("generic_html")
      expect(maryland.legislation_rules&.[](:engine)).to be_nil
      expect(maryland.hearings_rules&.[](:retrieval)).to eq("generic_html")
      expect(maryland.hearings_rules&.[](:parsing)).to eq("generic_html")
      expect(maryland.hearings_rules&.[](:engine)).to be_nil
      expect(maryland.vote_rules&.[](:retrieval)).to eq("maryland_general_assembly")
      expect(maryland.vote_rules&.[](:parsing)).to eq("generic_html")
      expect(maryland.vote_rules&.[](:engine)).to be_nil
      expect(maryland.roster_rules&.[](:retrieval)).to eq("open_states")
      expect(maryland.roster_rules&.[](:parsing)).to eq("open_states")
      expect(maryland.roster_rules&.[](:engine)).to be_nil
      expect(maryland.law_rules&.[](:retrieval)).to eq("configured_pdf_catalog")
      expect(maryland.law_rules&.[](:parsing)).to eq("pdf_statute_sections")
      expect(maryland.law_rules&.[](:engine)).to be_nil
      expect(maryland.law_rules&.[](:local_path)).to eq("raw")
      expect(maryland.law_rules&.dig(:endpoints, :catalog)).to eq("/mgawebsite/api/Laws/GetArticles")
      expect(maryland.law_rules&.dig(:endpoints, :article_link)).to eq("/mgawebsite/api/Laws/GetArticleLink")
      expect(maryland.law_rules&.dig(:params, :enactments)).to eq("true")

      congress = described_class.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
      expect(congress.legislation_rules&.[](:retrieval)).to eq("congress_dot_gov")
      expect(congress.legislation_rules&.[](:parsing)).to eq("congress_dot_gov")
      expect(congress.legislation_rules&.[](:engine)).to be_nil
      expect(congress.hearings_rules&.[](:retrieval)).to eq("generic_rest")
      expect(congress.hearings_rules&.[](:parsing)).to eq("generic_rest")
      expect(congress.hearings_rules&.[](:engine)).to be_nil
      expect(congress.vote_rules&.[](:retrieval)).to eq("congress_dot_gov")
      expect(congress.vote_rules&.[](:parsing)).to eq("congress_dot_gov")
      expect(congress.vote_rules&.[](:engine)).to be_nil
      expect(congress.roster_rules&.[](:retrieval)).to eq("congress_dot_gov")
      expect(congress.roster_rules&.[](:parsing)).to eq("congress_dot_gov")
      expect(congress.roster_rules&.[](:engine)).to be_nil
      expect(congress.law_rules&.[](:retrieval)).to eq("uslm_xml")
      expect(congress.law_rules&.[](:parsing)).to eq("uslm_xml")
      expect(congress.law_rules&.[](:engine)).to be_nil

      annapolis = described_class.read(File.join(described_class.default_directory, "annapolis-maryland-united_states.yml"))
      expect(annapolis.legislation_rules&.[](:retrieval)).to eq("legistar")
      expect(annapolis.legislation_rules&.[](:parsing)).to eq("legistar")
      expect(annapolis.legislation_rules&.[](:engine)).to be_nil
      expect(annapolis.legislation_rules&.[](:client)).to be_nil
      expect(annapolis.hearings_rules&.[](:retrieval)).to eq("legistar")
      expect(annapolis.hearings_rules&.[](:parsing)).to eq("legistar")
      expect(annapolis.hearings_rules&.[](:engine)).to be_nil
      expect(annapolis.hearings_rules&.[](:client)).to be_nil
      expect(annapolis.vote_rules&.[](:retrieval)).to eq("manual")
      expect(annapolis.vote_rules&.[](:parsing)).to eq("manual")
      expect(annapolis.vote_rules&.[](:engine)).to be_nil
      expect(annapolis.roster_rules&.[](:retrieval)).to eq("curated")
      expect(annapolis.roster_rules&.[](:parsing)).to eq("curated")
      expect(annapolis.roster_rules&.[](:engine)).to be_nil
      expect(annapolis.law_rules&.[](:retrieval)).to eq("unavailable")
      expect(annapolis.law_rules&.[](:parsing)).to eq("unavailable")
      expect(annapolis.law_rules&.[](:engine)).to be_nil
    end

    it "rejects integration rules that are not mappings" do
      Dir.mktmpdir do |dir|
        content = clean_base_yaml.call.sub("source_rules:\n", "source_rules:\n    legislation_rules: 'invalid_string'\n")
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules must be a mapping/)
      end
    end

    it "rejects integration rules missing retrieval" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        parsing: 'legistar'\n        base_url: 'https://example.com'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.retrieval must be a non-empty string/)
      end
    end

    it "rejects integration rules missing parsing" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        retrieval: 'legistar'\n        base_url: 'https://example.com'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.parsing must be a non-empty string/)
      end
    end

    it "rejects integration rules with empty retrieval" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        retrieval: ''\n        parsing: 'legistar'\n        base_url: 'https://example.com'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.retrieval must be a non-empty string/)
      end
    end

    it "rejects integration rules with empty parsing" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        retrieval: 'legistar'\n        parsing: ''\n        base_url: 'https://example.com'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.parsing must be a non-empty string/)
      end
    end

    it "rejects integration rules containing engine as an unknown field" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        engine: 'legistar'\n        retrieval: 'legistar'\n        parsing: 'legistar'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Unknown field "engine" in legislation_rules/)
      end
    end

    it "rejects integration rules containing client as an unknown field" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        retrieval: 'legistar'\n        parsing: 'legistar'\n        client: 'baltimore'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Unknown field "client" in legislation_rules/)
      end
    end

    it "rejects integration rules with non-string base_url" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    hearings_rules:\n        retrieval: 'generic_html'\n        parsing: 'generic_html'\n        base_url: 12345\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /hearings_rules\.base_url must be a non-empty string/)
      end
    end

    it "rejects integration rules with invalid metadata_mapping" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        retrieval: 'generic_rest'\n        parsing: 'generic_rest'\n        base_url: 'https://example.com'\n        metadata_mapping: 'not-a-hash'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.metadata_mapping must be a mapping/)
      end
    end

    it "rejects unknown fields inside integration rules" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    vote_rules:\n        retrieval: 'generic_csv'\n        parsing: 'generic_csv'\n        base_url: 'https://example.com'\n        unknown_field: 123\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Unknown field "unknown_field" in vote_rules/)
      end
    end

    it "rejects integration rules that are empty mappings" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules: {}\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.retrieval must be a non-empty string/)
      end
    end

    it "rejects integration rules that are blank non-mappings" do
      Dir.mktmpdir do |dir|
        [
          ["[]\n", "an empty sequence"],
          ["''\n", "an empty string"],
          ["'   '\n", "a whitespace string"],
          ["false\n", "a boolean"]
        ].each do |val_yaml, label|
          bad_rule = "source_rules:\n    legislation_rules: #{val_yaml}"
          content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(described_class::ValidationError, /legislation_rules must be a mapping/), "Expected #{label} to raise ValidationError"
        end
      end
    end

    %w[hearings_rules vote_rules roster_rules law_rules].each do |field|
      it "rejects empty hash #{field} ({}) due to missing retrieval" do
        Dir.mktmpdir do |dir|
          bad_rule = "source_rules:\n    #{field}: {}\n"
          content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(described_class::ValidationError, /#{field}\.retrieval must be a non-empty string/)
        end
      end

      it "rejects non-mapping values for #{field} (array, empty string, false)" do
        ["[]", "''", "false"].each do |raw_val|
          Dir.mktmpdir do |dir|
            bad_rule = "source_rules:\n    #{field}: #{raw_val}\n"
            content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
            file = File.join(dir, "baltimore-maryland-united_states.yml")
            File.write(file, content)

            expect {
              described_class.read(file)
            }.to raise_error(described_class::ValidationError, /#{field} must be a mapping/)
          end
        end
      end
    end

    it "accepts integration rules explicitly set to nil" do
      Dir.mktmpdir do |dir|
        nil_rule = "source_rules:\n    legislation_rules: ~\n"
        content = clean_base_yaml.call.sub("source_rules:\n", nil_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        doc = described_class.read(file)
        expect(doc.legislation_rules).to be_nil
        expect(doc.to_jurisdiction_rules.legislation_rules).to be_nil
      end
    end

    it "rejects top-level integration rules that are empty mappings or non-mappings" do
      Dir.mktmpdir do |dir|
        content_hash = clean_base_yaml.call + "\nlegislation_rules: {}\n"
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content_hash)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.retrieval must be a non-empty string/)

        content_seq = clean_base_yaml.call + "\nlegislation_rules: []\n"
        File.write(file, content_seq)
        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules must be a mapping/)
      end
    end
  end

  describe "legacy source properties removal" do
    it "does not expose deleted legacy source properties on JurisdictionRules" do
      doc = described_class.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
      j_rules = doc.to_jurisdiction_rules

      expect(j_rules.respond_to?(:roster_source)).to be(false)
      expect(j_rules.respond_to?(:roster_refresher)).to be(false)
      expect(j_rules.respond_to?(:vote_source)).to be(false)
      expect(j_rules.respond_to?(:legistar_client)).to be(false)
      expect(j_rules.respond_to?(:open_states_jurisdiction)).to be(false)
      expect(j_rules.respond_to?(:legislation_source)).to be(false)
      expect(j_rules.respond_to?(:law_source)).to be(false)
      expect(j_rules.respond_to?(:hearings_source)).to be(false)
    end

    it "rejects legacy source properties in source_rules with validation error" do
      Dir.mktmpdir do |dir|
        yaml_content = <<~YAML
          schema_version: 1
          city: "testcity"
          region: "maryland"
          region_code: "MD"
          country: "united_states"
          name: "testcity-maryland-united_states"
          legislative_sessions:
            - name: "2025-2029 Council"
              start_date: "2025-01-01"
              end_date: "2029-01-01"
              active: true
              upstream_name: "2025-2029 Council"
          time_zone: "America/New_York"
          icon_url: "https://example.com/icon.png"
          source_rules:
            publishes_legislator_votes: false
            chamber_label: "City Council"
            session_numbering: "term_years"
            default_bill_chamber: "council"
            bill_chambers:
              - "council"
            roster_source: "curated"
            roster_rules:
              retrieval: "curated"
              parsing: "curated"
            vote_rules:
              retrieval: "manual"
              parsing: "manual"
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
        file = File.join(dir, "testcity-maryland-united_states.yml")
        File.write(file, yaml_content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Unknown field "roster_source" in source_rules/)
      end
    end
  end

  describe "decoupled retrieval and parsing integration rules" do
    clean_base_yaml = lambda {
      content = File.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
      content = content.sub("vote_source: legistar", "vote_source: legistar\n    legistar_client: baltimore")
      content.sub(/\n\s+legislation_rules:.*?\nterm_rules:/m, "\n\nterm_rules:")
    }

    it "accepts integration rules defining explicit retrieval and parsing without engine" do
      Dir.mktmpdir do |dir|
        extra_rules = <<~YAML
          source_rules:
              legislation_rules:
                  retrieval: generic_rest
                  parsing: generic_json
                  base_url: "https://mgaleg.maryland.gov"
              hearings_rules:
                  retrieval: generic_html
                  parsing: generic_html
                  base_url: "https://mgaleg.maryland.gov/hearings"
              vote_rules:
                  retrieval: generic_csv
                  parsing: generic_csv
                  base_url: "https://mgaleg.maryland.gov/votes"
              roster_rules:
                  retrieval: generic_graphql
                  parsing: generic_graphql
                  base_url: "https://api.congress.gov/roster"
              law_rules:
                  retrieval: generic_rest
                  parsing: generic_xml
                  base_url: "https://mgaleg.maryland.gov/laws"
        YAML
        content = clean_base_yaml.call.sub("source_rules:\n", extra_rules)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        doc = described_class.read(file)
        expect(doc.legislation_rules).to eq({
          retrieval: "generic_rest",
          parsing: "generic_json",
          base_url: "https://mgaleg.maryland.gov"
        })
        expect(doc.hearings_rules).to eq({
          retrieval: "generic_html",
          parsing: "generic_html",
          base_url: "https://mgaleg.maryland.gov/hearings"
        })
        expect(doc.vote_rules).to eq({
          retrieval: "generic_csv",
          parsing: "generic_csv",
          base_url: "https://mgaleg.maryland.gov/votes"
        })
        expect(doc.roster_rules).to eq({
          retrieval: "generic_graphql",
          parsing: "generic_graphql",
          base_url: "https://api.congress.gov/roster"
        })
        expect(doc.law_rules).to eq({
          retrieval: "generic_rest",
          parsing: "generic_xml",
          base_url: "https://mgaleg.maryland.gov/laws"
        })

        j_rules = doc.to_jurisdiction_rules
        expect(j_rules.legislation_rules).to eq(doc.legislation_rules)
        expect(j_rules.hearings_rules).to eq(doc.hearings_rules)
        expect(j_rules.vote_rules).to eq(doc.vote_rules)
        expect(j_rules.roster_rules).to eq(doc.roster_rules)
        expect(j_rules.law_rules).to eq(doc.law_rules)
      end
    end

    it "accepts integration rules using retrieval_strategy and parser_format aliases" do
      Dir.mktmpdir do |dir|
        extra_rules = <<~YAML
          source_rules:
              legislation_rules:
                  retrieval_strategy: legistar
                  parser_format: legistar
                  base_url: "https://webapi.legistar.com/v1"
        YAML
        content = clean_base_yaml.call.sub("source_rules:\n", extra_rules)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        doc = described_class.read(file)
        expect(doc.legislation_rules).to eq({
          retrieval_strategy: "legistar",
          parser_format: "legistar",
          base_url: "https://webapi.legistar.com/v1"
        })
      end
    end

    it "rejects dual-defined rules containing legacy engine property" do
      Dir.mktmpdir do |dir|
        extra_rules = <<~YAML
          source_rules:
              legislation_rules:
                  engine: legistar
                  retrieval: legistar_api
                  parsing: legistar_feed
                  base_url: "https://webapi.legistar.com/v1"
        YAML
        content = clean_base_yaml.call.sub("source_rules:\n", extra_rules)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Unknown field "engine" in legislation_rules/)
      end
    end

    it "rejects integration rules with retrieval present but missing parsing" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        retrieval: 'generic_rest'\n        base_url: 'https://example.com'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.parsing must be a non-empty string/)
      end
    end

    it "rejects integration rules with parsing present but missing retrieval" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        parsing: 'generic_json'\n        base_url: 'https://example.com'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.retrieval must be a non-empty string/)
      end
    end

    it "rejects integration rules with empty retrieval string" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        retrieval: ''\n        parsing: 'generic_json'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.retrieval must be a non-empty string/)
      end
    end

    it "rejects integration rules with empty parsing string" do
      Dir.mktmpdir do |dir|
        bad_rule = "source_rules:\n    legislation_rules:\n        retrieval: 'generic_rest'\n        parsing: ''\n"
        content = clean_base_yaml.call.sub("source_rules:\n", bad_rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.parsing must be a non-empty string/)
      end
    end
  end

  describe "INTEGRATION_RULE_FIELDS" do
    it "includes legacy_path_fallback" do
      expect(described_class::INTEGRATION_RULE_FIELDS).to include("legacy_path_fallback")
    end

    it "includes generic_portal_urls" do
      expect(described_class::INTEGRATION_RULE_FIELDS).to include("generic_portal_urls")
    end

    it "includes evidence attribution properties, enable_historical_fallback, and timezone" do
      %w[evidence_publisher evidence_jurisdiction evidence_source_url enable_historical_fallback timezone].each do |field|
        expect(described_class::INTEGRATION_RULE_FIELDS).to include(field)
      end
    end
  end

  describe "evidence attribution validation in roster_rules" do
    clean_base_yaml = lambda {
      content = File.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
      content.sub(/\n\s+legislation_rules:.*?\nterm_rules:/m, "\n\nterm_rules:")
    }

    it "accepts non-empty strings for evidence attribution properties" do
      Dir.mktmpdir do |dir|
        rule = <<~YAML
          source_rules:
              roster_rules:
                  retrieval: curated
                  parsing: curated
                  evidence_publisher: "baltimorecity.gov"
                  evidence_jurisdiction: "baltimore_city"
                  evidence_source_url: "https://baltimorecity.gov"
        YAML
        content = clean_base_yaml.call.sub("source_rules:\n", rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        doc = described_class.read(file)
        expect(doc.roster_rules[:evidence_publisher]).to eq("baltimorecity.gov")
        expect(doc.roster_rules[:evidence_jurisdiction]).to eq("baltimore_city")
        expect(doc.roster_rules[:evidence_source_url]).to eq("https://baltimorecity.gov")
      end
    end

    it "rejects non-string values for evidence attribution properties" do
      %w[evidence_publisher evidence_jurisdiction evidence_source_url].each do |prop|
        Dir.mktmpdir do |dir|
          rule = "source_rules:\n    roster_rules:\n        retrieval: curated\n        parsing: curated\n        #{prop}: 12345\n"
          content = clean_base_yaml.call.sub("source_rules:\n", rule)
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(described_class::ValidationError, /roster_rules\.#{prop} must be a non-empty string/)
        end
      end
    end

    it "rejects empty string values for evidence attribution properties" do
      %w[evidence_publisher evidence_jurisdiction evidence_source_url].each do |prop|
        Dir.mktmpdir do |dir|
          rule = "source_rules:\n    roster_rules:\n        retrieval: curated\n        parsing: curated\n        #{prop}: ''\n"
          content = clean_base_yaml.call.sub("source_rules:\n", rule)
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(described_class::ValidationError, /roster_rules\.#{prop} must be a non-empty string/)
        end
      end
    end
  end

  describe "vote_rules validation" do
    clean_base_yaml = lambda {
      content = File.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
      content.sub(/\n\s+legislation_rules:.*?\nterm_rules:/m, "\n\nterm_rules:")
    }

    it "accepts boolean enable_historical_fallback and non-empty string timezone" do
      Dir.mktmpdir do |dir|
        rule = <<~YAML
          source_rules:
              vote_rules:
                  retrieval: manual
                  parsing: manual
                  enable_historical_fallback: true
                  timezone: "America/New_York"
        YAML
        content = clean_base_yaml.call.sub("source_rules:\n", rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        doc = described_class.read(file)
        expect(doc.vote_rules[:enable_historical_fallback]).to be(true)
        expect(doc.vote_rules[:timezone]).to eq("America/New_York")
      end
    end

    it "rejects non-boolean enable_historical_fallback" do
      Dir.mktmpdir do |dir|
        rule = "source_rules:\n    vote_rules:\n        retrieval: manual\n        parsing: manual\n        enable_historical_fallback: 'true'\n"
        content = clean_base_yaml.call.sub("source_rules:\n", rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /vote_rules\.enable_historical_fallback must be a boolean/)
      end
    end

    it "rejects non-string or empty string timezone" do
      Dir.mktmpdir do |dir|
        rule = "source_rules:\n    vote_rules:\n        retrieval: manual\n        parsing: manual\n        timezone: ''\n"
        content = clean_base_yaml.call.sub("source_rules:\n", rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /vote_rules\.timezone must be a non-empty string/)
      end

      Dir.mktmpdir do |dir|
        rule = "source_rules:\n    vote_rules:\n        retrieval: manual\n        parsing: manual\n        timezone: 123\n"
        content = clean_base_yaml.call.sub("source_rules:\n", rule)
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /vote_rules\.timezone must be a non-empty string/)
      end
    end
  end

  describe "generic_portal_urls validation" do
    it "accepts an array of strings in legislation_rules" do
      doc = described_class.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
      expect(doc.legislation_rules&.[](:generic_portal_urls)).to eq(
        ["https://baltimore.legistar.com", "https://baltimore.legistar.com/legislationsearch.aspx"]
      )
    end

    it "rejects generic_portal_urls when not an array of strings" do
      Dir.mktmpdir do |dir|
        content = File.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
        bad_content = content.sub(
          "generic_portal_urls:\n            - \"https://baltimore.legistar.com\"\n            - \"https://baltimore.legistar.com/legislationsearch.aspx\"",
          "generic_portal_urls: 'not-an-array'"
        )
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, bad_content)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /legislation_rules\.generic_portal_urls must be an array of strings/)
      end
    end
  end

  describe "legislative_sessions schema and sync (TASK-iwxrj.21)" do
    describe "parsing" do
      it "parses legislative_sessions into LegislativeSessionDefinition value objects" do
        doc = described_class.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
        sessions = doc.legislative_sessions
        expect(sessions.size).to eq(2)

        s1 = sessions[0]
        expect(s1.name).to eq("118th Congress")
        expect(s1.start_date).to eq(Date.new(2023, 1, 3))
        expect(s1.end_date).to eq(Date.new(2025, 1, 3))
        expect(s1.active).to be(false)
        expect(s1.active?).to be(false)
        expect(s1.upstream_name).to eq("118")

        s2 = sessions[1]
        expect(s2.name).to eq("119th Congress")
        expect(s2.start_date).to eq(Date.new(2025, 1, 3))
        expect(s2.end_date).to eq(Date.new(2027, 1, 3))
        expect(s2.active).to be(true)
        expect(s2.active?).to be(true)
        expect(s2.upstream_name).to eq("119")
      end

      it "parses upstream_name when explicitly declared in YAML" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, content)

          doc = described_class.read(file)
          expect(doc.legislative_sessions.first.upstream_name).to eq("118")
          expect(doc.legislative_sessions.last.upstream_name).to eq("119")
        end
      end

      it "falls back upstream_name to name when omitted or empty in YAML" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub(/ *upstream_name: "118"\n/, "")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          doc = described_class.read(file)
          expect(doc.legislative_sessions.first.upstream_name).to eq("118th Congress")
        end
      end

      it "defaults active to false when omitted from session YAML" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub(/ *active: false\n/, "")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          doc = described_class.read(file)
          expect(doc.legislative_sessions.first.active).to be(false)
          expect(doc.legislative_sessions.first.active?).to be(false)
        end
      end

      it "returns empty array when legislative_sessions is absent from YAML" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub(/legislative_sessions:\n.*?(?=time_zone:)/m, "")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          doc = described_class.read(file)
          expect(doc.legislative_sessions).to eq([])
        end
      end

      it "raises ValidationError when legislative_sessions is empty array in YAML" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub(/legislative_sessions:\n.*?(?=time_zone:)/m, "legislative_sessions: []\n")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /must have at least one active session/)
        end
      end

      it "parses native YAML Date objects when unquoted dates are used" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.gsub('"2023-01-03"', "2023-01-03").gsub('"2025-01-03"', "2025-01-03")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          doc = described_class.read(file)
          expect(doc.legislative_sessions.first.start_date).to eq(Date.new(2023, 1, 3))
          expect(doc.legislative_sessions.first.end_date).to eq(Date.new(2025, 1, 3))
        end
      end
    end

    describe "validation errors" do
      it "rejects non-array legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub(/legislative_sessions:\n.*?(?=time_zone:)/m, "legislative_sessions: \"not an array\"\n")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /legislative_sessions must be an array/)
        end
      end

      it "rejects empty array legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub(/legislative_sessions:\n.*?(?=time_zone:)/m, "legislative_sessions: []\n")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /must have at least one active session/)
        end
      end

      it "accepts omitted or nil legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml_omitted = content.sub(/legislative_sessions:\n.*?(?=time_zone:)/m, "")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml_omitted)

          expect { described_class.read(file) }.not_to raise_error
          doc_omitted = described_class.read(file)
          expect(doc_omitted.legislative_sessions).to eq([])

          yaml_nil = content.sub(/legislative_sessions:\n.*?(?=time_zone:)/m, "legislative_sessions: ~\n")
          File.write(file, yaml_nil)

          expect { described_class.read(file) }.not_to raise_error
          doc_nil = described_class.read(file)
          expect(doc_nil.legislative_sessions).to eq([])
        end
      end

      it "rejects non-mapping items within legislative_sessions array" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub(/legislative_sessions:\n.*?(?=time_zone:)/m, "legislative_sessions:\n    - \"string item\"\n")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /legislative_session must be a mapping/)
        end
      end

      it "rejects missing required field name in legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub('name: "118th Congress"', "")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Missing required field "name"/)
        end
      end

      it "rejects blank string name in legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub('name: "118th Congress"', 'name: "   "')
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /name must be a non-empty string/)
        end
      end

      it "rejects missing required field start_date in legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub('start_date: "2023-01-03"', "")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Missing required field "start_date"/)
        end
      end

      it "rejects missing required field end_date in legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub('end_date: "2025-01-03"', "")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Missing required field "end_date"/)
        end
      end

      it "rejects invalid date format in legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub('start_date: "2023-01-03"', 'start_date: "not-a-date"')
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Expected ISO8601 date/)
        end
      end

      it "rejects legislative_sessions with end_date before start_date" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub('end_date: "2025-01-03"', 'end_date: "2022-01-03"')
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /end_date must be on or after start_date/)
        end
      end

      it "accepts single-day session where end_date equals start_date" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub('end_date: "2025-01-03"', 'end_date: "2023-01-03"')
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          doc = described_class.read(file)
          expect(doc.legislative_sessions.first.end_date).to eq(doc.legislative_sessions.first.start_date)
        end
      end

      it "rejects duplicate session names in legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub('name: "119th Congress"', 'name: "118th Congress"')
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Duplicate legislative session name "118th Congress"/)
        end
      end

      it "rejects non-boolean active field in legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub("active: false", "active: \"not_a_bool\"")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /active must be a boolean/)
        end
      end

      it "rejects unknown fields in legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub('name: "118th Congress"', "name: \"118th Congress\"\n      extra_opt: true")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Unknown field "extra_opt" in legislative_sessions/)
        end
      end

      it "rejects legislative_sessions when no session is marked active" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.gsub("active: true", "active: false")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /must have at least one active session/)
        end
      end

      it "rejects non-string or empty upstream_name in legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub('upstream_name: "118"', "upstream_name: 118")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /upstream_name must be a non-empty string/)

          empty_yaml = content.sub('upstream_name: "118"', 'upstream_name: "   "')
          File.write(file, empty_yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /upstream_name must be a non-empty string/)
        end
      end
    end

    describe "#sync_legislative_sessions!" do
      it "destroys orphaned sessions not present in YAML and upserts declared sessions" do
        doc = described_class.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
        locale = create(:sway_locale)

        # Pre-existing session not listed in YAML with an associated bill
        orphaned = create(:legislative_session, sway_locale: locale, name: "117th Congress")
        bill = create(:bill, sway_locale: locale, legislative_session: orphaned)

        # Initial sync
        synced = doc.sync_legislative_sessions!(locale)
        expect(synced.size).to eq(2)
        expect(locale.legislative_sessions.count).to eq(2)
        expect(LegislativeSession.find_by(id: orphaned.id)).to be_nil
        expect(bill.reload.legislative_session_id).to be_nil

        s118 = locale.legislative_sessions.find_by(name: "118th Congress")
        expect(s118.start_date).to eq(Date.new(2023, 1, 3))
        expect(s118.end_date).to eq(Date.new(2025, 1, 3))
        expect(s118.active).to be(false)

        s119 = locale.legislative_sessions.find_by(name: "119th Congress")
        expect(s119.start_date).to eq(Date.new(2025, 1, 3))
        expect(s119.end_date).to eq(Date.new(2027, 1, 3))
        expect(s119.active).to be(true)

        # Idempotency check: repeated sync does not create duplicate rows
        expect { doc.sync_legislative_sessions!(locale) }.not_to change(LegislativeSession, :count)

        # Updating YAML updates attributes on existing record in place
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          updated_yaml = content.sub("active: false", "active: true")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, updated_yaml)
          updated_doc = described_class.read(file)
          updated_doc.sync_legislative_sessions!(locale)

          expect(s118.reload.active).to be(true)
        end
      end

      it "destroys all existing sessions and nullifies associated bills when doc has omitted legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub(/legislative_sessions:\n.*?(?=time_zone:)/m, "")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          locale = create(:sway_locale)
          doc = described_class.read(file)
          pre_existing = create(:legislative_session, sway_locale: locale, name: "Existing Session")
          bill = create(:bill, sway_locale: locale, legislative_session: pre_existing)

          expect { doc.sync_legislative_sessions!(locale) }.to change(LegislativeSession, :count).by(-1)
          expect { pre_existing.reload }.to raise_error(ActiveRecord::RecordNotFound)
          expect(bill.reload.legislative_session_id).to be_nil
        end
      end

      it "destroys all existing sessions and nullifies associated bills when doc has explicit nil legislative_sessions" do
        Dir.mktmpdir do |dir|
          content = File.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
          yaml = content.sub(/legislative_sessions:\n.*?(?=time_zone:)/m, "legislative_sessions: ~\n")
          file = File.join(dir, "congress-congress-united_states.yml")
          File.write(file, yaml)

          locale = create(:sway_locale)
          doc = described_class.read(file)
          expect(doc.legislative_sessions).to eq([])

          pre_existing = create(:legislative_session, sway_locale: locale, name: "Existing Session")
          bill = create(:bill, sway_locale: locale, legislative_session: pre_existing)

          synced = doc.sync_legislative_sessions!(locale)
          expect(synced).to eq([])
          expect { pre_existing.reload }.to raise_error(ActiveRecord::RecordNotFound)
          expect(bill.reload.legislative_session_id).to be_nil
        end
      end

      it "raises ArgumentError if sway_locale is unpersisted or nil" do
        doc = described_class.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))

        expect { doc.sync_legislative_sessions!(nil) }.to raise_error(ArgumentError, /persisted/)
        expect { doc.sync_legislative_sessions!(SwayLocale.new) }.to raise_error(ArgumentError, /persisted/)
      end
    end

    describe "live YAML definitions" do
      it "ensures every discoverable SwayLocale defines non-empty legislative_sessions with exactly one active session" do
        docs = described_class.discover
        expect(docs).not_to be_empty

        docs.each do |doc|
          sessions = doc.legislative_sessions
          expect(sessions).not_to be_empty,
            "Expected #{doc.filename || doc.name} to define legislative_sessions, but was empty"

          active_sessions = sessions.select(&:active?)
          expect(active_sessions.size).to eq(1),
            "Expected #{doc.filename || doc.name} to have exactly 1 active legislative session, but found #{active_sessions.size} (#{active_sessions.map(&:name).join(", ")})"

          sessions.each do |session|
            expect(session.name).to be_present
            expect(session.upstream_name).to be_present
            expect(session.start_date).to be_a(Date)
            expect(session.end_date).to be_a(Date)
            expect(session.end_date).to be >= session.start_date
          end
        end
      end

      it "verifies expected session details for core jurisdictions" do
        baltimore = described_class.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
        expect(baltimore.legislative_sessions.map(&:name)).to eq(["72nd City Council", "73rd City Council"])
        expect(baltimore.legislative_sessions.map(&:upstream_name)).to eq(["72nd City Council", "73rd City Council"])
        expect(baltimore.legislative_sessions.find { |s| s.name == "73rd City Council" }&.active?).to be(true)

        maryland = described_class.read(File.join(described_class.default_directory, "maryland-maryland-united_states.yml"))
        expect(maryland.legislative_sessions.map(&:name)).to eq(["2024 Regular Session", "2025 Regular Session", "2026 Regular Session"])
        expect(maryland.legislative_sessions.map(&:upstream_name)).to eq(["2024RS", "2025RS", "2026RS"])
        expect(maryland.legislative_sessions.find { |s| s.name == "2026 Regular Session" }&.active?).to be(true)

        annapolis = described_class.read(File.join(described_class.default_directory, "annapolis-maryland-united_states.yml"))
        expect(annapolis.legislative_sessions.map(&:name)).to eq(["2021-2025 City Council", "2025-2029 City Council"])
        expect(annapolis.legislative_sessions.map(&:upstream_name)).to eq(["2021-2025 City Council", "2025-2029 City Council"])
        expect(annapolis.legislative_sessions.find { |s| s.name == "2025-2029 City Council" }&.active?).to be(true)

        congress = described_class.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
        expect(congress.legislative_sessions.map(&:name)).to eq(["118th Congress", "119th Congress"])
        expect(congress.legislative_sessions.map(&:upstream_name)).to eq(["118", "119"])
        expect(congress.legislative_sessions.find { |s| s.name == "119th Congress" }&.active?).to be(true)
      end
    end
  end

  describe "nominatim geographic configuration" do
    clean_base_yaml = lambda {
      yaml = File.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
      yaml.gsub(/^nominatim_[a-z_]+:.*$\n?/, "")
    }

    describe "schema constants" do
      it "defines NOMINATIM_FIELDS with the three geographic configuration keys" do
        expect(described_class::NOMINATIM_FIELDS).to eq(%w[
          nominatim_viewbox
          nominatim_bounded
          nominatim_country_codes
        ])
        expect(described_class::NOMINATIM_FIELDS).to be_frozen
      end

      it "includes NOMINATIM_FIELDS in TOP_LEVEL_FIELDS" do
        described_class::NOMINATIM_FIELDS.each do |field|
          expect(described_class::TOP_LEVEL_FIELDS).to include(field)
        end
      end
    end

    describe "successful parsing and document accessors" do
      it "parses valid viewbox, bounded, and country codes attributes" do
        Dir.mktmpdir do |dir|
          extra_config = <<~YAML
            nominatim_viewbox: "-76.7114,39.3720,-76.5297,39.1972"
            nominatim_bounded: true
            nominatim_country_codes: "us"
          YAML
          content = clean_base_yaml.call + "\n" + extra_config
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          doc = described_class.read(file)
          expect(doc.nominatim_viewbox).to eq("-76.7114,39.3720,-76.5297,39.1972")
          expect(doc.nominatim_bounded).to be(true)
          expect(doc.nominatim_country_codes).to eq("us")
          expect(doc.to_h).to include(
            nominatim_viewbox: "-76.7114,39.3720,-76.5297,39.1972",
            nominatim_bounded: true,
            nominatim_country_codes: "us"
          )
        end
      end

      it "accepts integer coordinates and opposite hemisphere coordinates in nominatim_viewbox" do
        Dir.mktmpdir do |dir|
          extra_config = <<~YAML
            nominatim_viewbox: "12,-34,-56,78"
            nominatim_bounded: false
            nominatim_country_codes: "us,ca"
          YAML
          content = clean_base_yaml.call + "\n" + extra_config
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          doc = described_class.read(file)
          expect(doc.nominatim_viewbox).to eq("12,-34,-56,78")
          expect(doc.nominatim_bounded).to be(false)
          expect(doc.nominatim_country_codes).to eq("us,ca")
        end
      end

      it "accepts omitted Nominatim fields and returns nil for accessors" do
        Dir.mktmpdir do |dir|
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, clean_base_yaml.call)

          doc = described_class.read(file)
          expect(doc.nominatim_viewbox).to be_nil
          expect(doc.nominatim_bounded).to be_nil
          expect(doc.nominatim_country_codes).to be_nil
          expect(doc.to_h).to include(
            nominatim_viewbox: nil,
            nominatim_bounded: nil,
            nominatim_country_codes: nil
          )
        end
      end

      it "accepts explicit nil values for Nominatim fields" do
        Dir.mktmpdir do |dir|
          extra_config = <<~YAML
            nominatim_viewbox: ~
            nominatim_bounded: ~
            nominatim_country_codes: ~
          YAML
          content = clean_base_yaml.call + "\n" + extra_config
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          doc = described_class.read(file)
          expect(doc.nominatim_viewbox).to be_nil
          expect(doc.nominatim_bounded).to be_nil
          expect(doc.nominatim_country_codes).to be_nil
        end
      end
    end

    describe "nominatim_viewbox validation" do
      it "rejects non-coordinate strings" do
        Dir.mktmpdir do |dir|
          content = clean_base_yaml.call + "\nnominatim_viewbox: 'baltimore_bounding_box'\n"
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(
            described_class::ValidationError,
            /nominatim_viewbox must be a comma-separated coordinate string '<min_lon>,<max_lat>,<max_lon>,<min_lat>'/
          )
        end
      end

      it "rejects incomplete coordinate tuples (less than 4 components)" do
        Dir.mktmpdir do |dir|
          content = clean_base_yaml.call + "\nnominatim_viewbox: '-76.7114,39.3720,-76.5297'\n"
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(
            described_class::ValidationError,
            /nominatim_viewbox must be a comma-separated coordinate string/
          )
        end
      end

      it "rejects coordinate tuples with more than 4 components" do
        Dir.mktmpdir do |dir|
          content = clean_base_yaml.call + "\nnominatim_viewbox: '-76.7114,39.3720,-76.5297,39.1972,10.0'\n"
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(
            described_class::ValidationError,
            /nominatim_viewbox must be a comma-separated coordinate string/
          )
        end
      end

      it "rejects coordinate strings containing alphabetic or special characters" do
        Dir.mktmpdir do |dir|
          content = clean_base_yaml.call + "\nnominatim_viewbox: '-76.7114,39.3720,abc,39.1972'\n"
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(
            described_class::ValidationError,
            /nominatim_viewbox must be a comma-separated coordinate string/
          )
        end
      end

      it "rejects non-string types for nominatim_viewbox" do
        Dir.mktmpdir do |dir|
          [
            "[-76.7114, 39.3720, -76.5297, 39.1972]",
            "12345",
            "true",
            "{min_lon: -76.7114}"
          ].each do |invalid_val|
            content = clean_base_yaml.call + "\nnominatim_viewbox: #{invalid_val}\n"
            file = File.join(dir, "baltimore-maryland-united_states.yml")
            File.write(file, content)

            expect {
              described_class.read(file)
            }.to raise_error(
              described_class::ValidationError,
              /nominatim_viewbox must be a comma-separated coordinate string/
            )
          end
        end
      end

      it "rejects blank or empty string for nominatim_viewbox" do
        Dir.mktmpdir do |dir|
          content = clean_base_yaml.call + "\nnominatim_viewbox: ''\n"
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(
            described_class::ValidationError,
            /nominatim_viewbox must be a comma-separated coordinate string/
          )
        end
      end
    end

    describe "nominatim_bounded validation" do
      it "rejects non-boolean values for nominatim_bounded" do
        Dir.mktmpdir do |dir|
          [
            "'true'",
            "'false'",
            "1",
            "0",
            "[true]",
            "{bounded: true}"
          ].each do |invalid_val|
            content = clean_base_yaml.call + "\nnominatim_bounded: #{invalid_val}\n"
            file = File.join(dir, "baltimore-maryland-united_states.yml")
            File.write(file, content)

            expect {
              described_class.read(file)
            }.to raise_error(
              described_class::ValidationError,
              /nominatim_bounded must be a boolean/
            )
          end
        end
      end
    end

    describe "nominatim_country_codes validation" do
      it "rejects empty string for nominatim_country_codes" do
        Dir.mktmpdir do |dir|
          content = clean_base_yaml.call + "\nnominatim_country_codes: ''\n"
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(
            described_class::ValidationError,
            /nominatim_country_codes must be a non-empty string/
          )
        end
      end

      it "rejects whitespace-only string for nominatim_country_codes" do
        Dir.mktmpdir do |dir|
          content = clean_base_yaml.call + "\nnominatim_country_codes: '   '\n"
          file = File.join(dir, "baltimore-maryland-united_states.yml")
          File.write(file, content)

          expect {
            described_class.read(file)
          }.to raise_error(
            described_class::ValidationError,
            /nominatim_country_codes must be a non-empty string/
          )
        end
      end

      it "rejects non-string types for nominatim_country_codes" do
        Dir.mktmpdir do |dir|
          [
            "['us']",
            "840",
            "true",
            "{code: 'us'}"
          ].each do |invalid_val|
            content = clean_base_yaml.call + "\nnominatim_country_codes: #{invalid_val}\n"
            file = File.join(dir, "baltimore-maryland-united_states.yml")
            File.write(file, content)

            expect {
              described_class.read(file)
            }.to raise_error(
              described_class::ValidationError,
              /nominatim_country_codes must be a non-empty string/
            )
          end
        end
      end
    end

    describe "live YAML definitions" do
      it "ensures every discoverable SwayLocale defines valid Nominatim geographic configurations" do
        docs = described_class.discover
        expect(docs).not_to be_empty

        docs.each do |doc|
          expect([true, false]).to include(doc.nominatim_bounded),
            "Expected #{doc.filename || doc.name} to define boolean nominatim_bounded, got #{doc.nominatim_bounded.inspect}"

          expect(doc.nominatim_country_codes).to be_a(String),
            "Expected #{doc.filename || doc.name} to define string nominatim_country_codes, got #{doc.nominatim_country_codes.inspect}"
          expect(doc.nominatim_country_codes).to be_present

          if doc.nominatim_viewbox.present?
            expect(doc.nominatim_viewbox).to match(/\A-?\d+(\.\d+)?,-?\d+(\.\d+)?,-?\d+(\.\d+)?,-?\d+(\.\d+)?\z/),
              "Expected #{doc.filename || doc.name} to have valid coordinate viewbox format, got #{doc.nominatim_viewbox.inspect}"
          end
        end
      end

      it "verifies expected geographic boundary values for all supported jurisdictions" do
        baltimore = described_class.read(File.join(described_class.default_directory, "baltimore-maryland-united_states.yml"))
        expect(baltimore.nominatim_viewbox).to eq("-76.7114,39.3720,-76.5297,39.1972")
        expect(baltimore.nominatim_bounded).to be(true)
        expect(baltimore.nominatim_country_codes).to eq("us")

        annapolis = described_class.read(File.join(described_class.default_directory, "annapolis-maryland-united_states.yml"))
        expect(annapolis.nominatim_viewbox).to eq("-76.5450,39.0200,-76.4650,38.9400")
        expect(annapolis.nominatim_bounded).to be(true)
        expect(annapolis.nominatim_country_codes).to eq("us")

        maryland = described_class.read(File.join(described_class.default_directory, "maryland-maryland-united_states.yml"))
        expect(maryland.nominatim_viewbox).to eq("-79.4877,39.7230,-75.0489,37.9117")
        expect(maryland.nominatim_bounded).to be(true)
        expect(maryland.nominatim_country_codes).to eq("us")

        congress = described_class.read(File.join(described_class.default_directory, "congress-congress-united_states.yml"))
        expect(congress.nominatim_viewbox).to be_nil
        expect(congress.nominatim_bounded).to be(false)
        expect(congress.nominatim_country_codes).to eq("us")
      end
    end
  end

  describe "legacy session start date fields rejection" do
    it "rejects current_legislative_session_start_date as an unknown schema field" do
      Dir.mktmpdir do |dir|
        yaml = <<~YAML
          schema_version: 1
          city: baltimore
          region: maryland
          country: united_states
          name: baltimore-maryland-united_states
          current_legislative_session_start_date: "2024-12-05"
          time_zone: America/New_York
          source_rules:
            publishes_legislator_votes: false
            chamber_label: City Council
            session_numbering: term_years
            default_bill_chamber: council
            bill_chambers: [council]
          term_rules:
            cycle_anchor_year: 2024
            cycle_years: 4
            identified_by: seat
        YAML
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, yaml)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Unknown schema field "current_legislative_session_start_date"/)
      end
    end

    it "rejects next_legislative_session_start_date as an unknown schema field" do
      Dir.mktmpdir do |dir|
        yaml = <<~YAML
          schema_version: 1
          city: baltimore
          region: maryland
          country: united_states
          name: baltimore-maryland-united_states
          next_legislative_session_start_date: "2028-12-07"
          time_zone: America/New_York
          source_rules:
            publishes_legislator_votes: false
            chamber_label: City Council
            session_numbering: term_years
            default_bill_chamber: council
            bill_chambers: [council]
          term_rules:
            cycle_anchor_year: 2024
            cycle_years: 4
            identified_by: seat
        YAML
        file = File.join(dir, "baltimore-maryland-united_states.yml")
        File.write(file, yaml)

        expect {
          described_class.read(file)
        }.to raise_error(described_class::ValidationError, /Unknown schema field "next_legislative_session_start_date"/)
      end
    end
  end

  # @lat: [[news-source-configuration#News source configuration contract]]
  describe "news_sources schema, digest, and sync" do
    synthetic_yaml_template = <<~YAML
      schema_version: 1
      city: "synthetic"
      region: "maryland"
      region_code: "MD"
      country: "united_states"
      name: "synthetic-maryland-united_states"
      time_zone: "America/New_York"
      icon_url: "logo.svg"
      source_rules:
        publishes_legislator_votes: false
        chamber_label: "Synthetic Council"
        session_numbering: "term_years"
        default_bill_chamber: "council"
        bill_chambers:
          - "council"
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
        identified_by: "seat"
      legislative_sessions:
        - name: "2025 Synthetic Council"
          start_date: "2025-01-01"
          end_date: "2029-01-01"
          active: true
          upstream_name: "2025 Synthetic Council"
      news_sources:
        - url: "https://synthetic.news.org/city/"
          path_policy: search_hint
        - url: "https://restricted.gazette.com/politics/"
          path_policy: restrict
    YAML

    describe "parsing and accessors" do
      it "parses news_sources and round-trips path policies exactly" do
        Dir.mktmpdir do |dir|
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, synthetic_yaml_template)

          doc = described_class.read(file)
          expect(doc.news_sources).to eq([
            {"url" => "https://synthetic.news.org/city/", "path_policy" => "search_hint"},
            {"url" => "https://restricted.gazette.com/politics/", "path_policy" => "restrict"}
          ])
        end
      end

      it "accepts an empty array of news_sources to explicitly disable news discovery" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub(/news_sources:\n.*/m, "news_sources: []\n")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          doc = described_class.read(file)
          expect(doc.news_sources).to eq([])
        end
      end

      it "calculates deterministic source_config_digest which changes when sources change" do
        Dir.mktmpdir do |dir|
          file1 = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file1, synthetic_yaml_template)
          doc1 = described_class.read(file1)

          digest1 = doc1.source_config_digest
          expect(digest1).to be_a(String)
          expect(digest1.length).to eq(64)

          expect(described_class.read(file1).source_config_digest).to eq(digest1)

          yaml2 = synthetic_yaml_template.sub("path_policy: search_hint", "path_policy: restrict")
          file2 = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file2, yaml2)
          doc2 = described_class.read(file2)
          expect(doc2.source_config_digest).not_to eq(digest1)

          yaml3 = synthetic_yaml_template.sub(/\n\s+- url: "https:\/\/restricted\.gazette\.com\/politics\/".*?path_policy: restrict/m, "")
          file3 = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file3, yaml3)
          doc3 = described_class.read(file3)
          expect(doc3.source_config_digest).not_to eq(digest1)
          expect(doc3.source_config_digest).not_to eq(doc2.source_config_digest)

          yaml_empty = synthetic_yaml_template.sub(/news_sources:\n.*/m, "news_sources: []\n")
          file_empty = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file_empty, yaml_empty)
          doc_empty = described_class.read(file_empty)
          expect(doc_empty.source_config_digest).not_to eq(digest1)
          expect(doc_empty.source_config_digest).to eq(Digest::SHA256.hexdigest([].to_json))
        end
      end

      it "implements .current_for to retrieve document by slug or SwayLocale" do
        doc = described_class.current_for("baltimore-maryland-united_states")
        expect(doc).to be_a(described_class::Document)
        expect(doc.name).to eq("baltimore-maryland-united_states")
        expect(doc.news_sources).not_to be_empty
      end
    end

    describe "authoritative configuration vs stale instruction DB row" do
      it "supplies configured newsroom sources over stale instruction DB row" do
        Dir.mktmpdir do |dir|
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, synthetic_yaml_template)
          doc = described_class.read(file)

          locale = create(:sway_locale, city: "synthetic", region_name: "maryland", country: "united_states")
          instruction = create(
            :llm_bill_summarization_instruction,
            sway_locale: locale,
            legislative_body_makeup: "Custom legislative body makeup",
            worked_example: "Custom worked example",
            news_media_website_urls: ["https://stale.news.org/"]
          )

          expect(doc.news_sources.map { |s| s["url"] }).to eq([
            "https://synthetic.news.org/city/",
            "https://restricted.gazette.com/politics/"
          ])

          allow(described_class).to receive(:current_for).with(locale.name, any_args).and_return(doc)
          allow(described_class).to receive(:find).with(locale.name, any_args).and_return(doc)

          instruction.update_column(:news_media_website_urls, ["https://unauthorized-override.org/"])
          expect(instruction.news_sources).to eq(doc.news_sources)
          expect(instruction.allowed_domains).to eq([
            "synthetic.news.org/city",
            "restricted.gazette.com/politics"
          ])
        end
      end
    end

    describe "schema and URI validation" do
      it "rejects missing news_sources field" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub(/news_sources:\n.*/m, "")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Missing required field "news_sources"/)
        end
      end

      it "rejects null news_sources field" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub(/news_sources:\n.*/m, "news_sources: null\n")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Missing required field "news_sources"/)
        end
      end

      it "rejects non-array news_sources" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub(/news_sources:\n.*/m, "news_sources: \"not an array\"\n")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /news_sources must be an array/)
        end
      end

      it "rejects non-mapping items within news_sources" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub(/news_sources:\n.*/m, "news_sources:\n  - \"https://example.com\"\n")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /news_source must be a mapping/)
        end
      end

      it "rejects unknown fields within news_sources mapping" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub("path_policy: search_hint", "path_policy: search_hint\n    extra_field: true")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Unknown field "extra_field" in news_sources/)
        end
      end

      it "rejects missing required field url in news_sources" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub('url: "https://synthetic.news.org/city/"', "")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Missing required field "url"/)
        end
      end

      it "rejects missing required field path_policy in news_sources" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub("path_policy: search_hint", "")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Missing required field "path_policy"/)
        end
      end

      it "rejects unknown path_policy in news_sources" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub("path_policy: search_hint", "path_policy: 'unsupported_policy'")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /"unsupported_policy" is not permitted\. Allowed values: \["search_hint", "restrict"\]/)
        end
      end

      it "rejects non-HTTPS URLs" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", "http://synthetic.news.org/city/")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /url must use https scheme/)
        end
      end

      it "rejects scheme-less URLs" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", "synthetic.news.org/city/")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /url must use https scheme/)
        end
      end

      it "rejects bare https:// URLs without authority" do
        Dir.mktmpdir do |dir|
          ["https://", "  https://  "].each do |bare_url|
            yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", bare_url)
            file = File.join(dir, "synthetic-maryland-united_states.yml")
            File.write(file, yaml)

            expect { described_class.read(file) }
              .to raise_error(described_class::ValidationError, /url host is invalid/)
          end
        end
      end

      it "rejects URLs containing credentials" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", "https://user:pass@synthetic.news.org/city/")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /url must not contain userinfo or credentials/)
        end
      end

      it "rejects URLs containing IP literals across all formats (decimal, octal, hex, dword, short-form)" do
        Dir.mktmpdir do |dir|
          ip_urls = [
            "https://127.0.0.1/news",
            "https://192.168.1.1/news",
            "https://10.0.0.1/news",
            "https://0.0.0.0/news",
            "https://0177.0.0.1/news",
            "https://0177.0.0.1:443/news",
            "https://012.0.0.1/news",
            "https://0300.0250.0.1/news",
            "https://0251.0376.0251.0376/latest/meta-data",
            "https://00177.000.000.001/news",
            "https://0x7f.0.0.1/news",
            "https://0x7f.0.0.1:443/news",
            "https://0X7F.0.0.1/news",
            "https://0x0a.0.0.1/news",
            "https://0xc0.0xa8.0.1/news",
            "https://0xa9.0xfe.0xa9.0xfe/latest/meta-data",
            "https://0x7f.0x0.0x0.0x1/news",
            "https://0177.0x0.0.1/news",
            "https://127.0x0.0.01/news",
            "https://127.1/news",
            "https://127.0.1/news",
            "https://0177.1/news",
            "https://0x7f.1/news",
            "https://0x7f.0.1/news",
            "https://10.1/news",
            "https://2130706433/",
            "https://2852039166/",
            "https://3232235521/",
            "https://0/",
            "https://0x7f000001/",
            "https://0xa9fea9fe/",
            "https://017700000001/",
            "https://127.0.0.1./news",
            "https://0177.0.0.1./news",
            "https://0x7f.0.0.1./news",
            "https://[::1]/news",
            "https://[2001:db8::1]/news",
            "https://[fe80::1]/news",
            "https://[::ffff:127.0.0.1]/news",
            "https://[::ffff:7f00:1]/news",
            "https://[::ffff:169.254.169.254]/latest/meta-data"
          ]

          ip_urls.each do |ip_url|
            yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", ip_url)
            file = File.join(dir, "synthetic-maryland-united_states.yml")
            File.write(file, yaml)

            expect { described_class.read(file) }
              .to raise_error(described_class::ValidationError, /url must not use an IP literal host/)
          end
        end
      end

      it "accepts legitimate newsroom domains with numeric or hex-like labels" do
        Dir.mktmpdir do |dir|
          legitimate_urls = [
            "https://123.news/politics",
            "https://360.cn/news",
            "https://163.com/news",
            "https://99acres.com/news",
            "https://0x7f.com/articles",
            "https://0xabc.news/feed",
            "https://news.0x7f.com/local",
            "https://sub.domain.123.com/news"
          ]

          legitimate_urls.each do |valid_url|
            yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", valid_url)
            file = File.join(dir, "synthetic-maryland-united_states.yml")
            File.write(file, yaml)

            doc = described_class.read(file)
            expect(doc.news_sources.first["url"]).to eq(valid_url)
          end
        end
      end

      it "rejects URLs with local or private destinations" do
        Dir.mktmpdir do |dir|
          [
            "https://localhost/news",
            "https://sub.localhost/news",
            "https://app.local/news",
            "https://news.test/articles",
            "https://news.example/articles",
            "https://news.invalid/articles",
            "https://host.docker.internal/news",
            "https://singlelabelhost/news"
          ].each do |bad_url|
            yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", bad_url)
            file = File.join(dir, "synthetic-maryland-united_states.yml")
            File.write(file, yaml)

            expect { described_class.read(file) }
              .to raise_error(described_class::ValidationError, /url must not target a local or private destination/)
          end
        end
      end

      it "rejects URLs with all-numeric or 0x-prefixed top-level domains" do
        Dir.mktmpdir do |dir|
          [
            "https://news.123/articles",
            "https://news.0/",
            "https://news.0x12/",
            "https://something.0x12/path"
          ].each do |invalid_tld_url|
            yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", invalid_tld_url)
            file = File.join(dir, "synthetic-maryland-united_states.yml")
            File.write(file, yaml)

            expect { described_class.read(file) }
              .to raise_error(described_class::ValidationError, /url host has invalid or numeric top-level domain/)
          end
        end
      end

      it "rejects URLs specifying custom ports" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", "https://synthetic.news.org:8443/city/")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /url must not specify a custom port/)
        end
      end

      it "rejects duplicate URLs in news_sources" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template + "  - url: \"https://synthetic.news.org/city/\"\n    path_policy: restrict\n"
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Duplicate news source URL/)
        end
      end

      it "rejects URLs containing empty or delimiter-only userinfo" do
        Dir.mktmpdir do |dir|
          [
            "https://@synthetic.news.org/city/",
            "https://:@synthetic.news.org/city/",
            "https://:secret@synthetic.news.org/city/",
            "https://user@synthetic.news.org/city/",
            "https://user%3Asecret@synthetic.news.org/city/"
          ].each do |bad_url|
            yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", bad_url)
            file = File.join(dir, "synthetic-maryland-united_states.yml")
            File.write(file, yaml)

            expect { described_class.read(file) }
              .to raise_error(described_class::ValidationError, /url must not contain userinfo or credentials/)
          end
        end
      end

      it "accepts valid URLs containing @ in the path" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", "https://synthetic.news.org/@opinion/city/")
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          doc = described_class.read(file)
          expect(doc.news_sources.first["url"]).to eq("https://synthetic.news.org/@opinion/city/")
        end
      end

      it "rejects URLs with .lan and .home.arpa local/private destinations" do
        Dir.mktmpdir do |dir|
          [
            "https://news.lan/articles",
            "https://sub.news.lan/articles",
            "https://news.home.arpa/articles",
            "https://home.arpa/articles"
          ].each do |bad_url|
            yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", bad_url)
            file = File.join(dir, "synthetic-maryland-united_states.yml")
            File.write(file, yaml)

            expect { described_class.read(file) }
              .to raise_error(described_class::ValidationError, /url must not target a local or private destination/)
          end
        end
      end

      it "rejects duplicate URLs in news_sources differing only in host case" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template + "  - url: \"https://SYNTHETIC.NEWS.ORG/city/\"\n    path_policy: restrict\n"
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Duplicate news source URL/)
        end
      end

      it "rejects duplicate URLs in news_sources differing only in whitespace padding" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template + "  - url: \"  https://synthetic.news.org/city/  \"\n    path_policy: restrict\n"
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Duplicate news source URL/)
        end
      end

      it "normalizes URL scheme and host to lowercase and strips whitespace in doc.news_sources while preserving path/query/fragment casing" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template.sub(
            "https://synthetic.news.org/city/",
            "  HTTPS://BALTIMORESUN.COM/News/Local?Sort=Desc#TopSection  "
          )
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          doc = described_class.read(file)
          expect(doc.news_sources.first["url"]).to eq("https://baltimoresun.com/News/Local?Sort=Desc#TopSection")
        end
      end

      it "produces identical source_config_digest regardless of host casing or whitespace in YAML" do
        Dir.mktmpdir do |dir1|
          Dir.mktmpdir do |dir2|
            yaml_clean = synthetic_yaml_template.sub(
              "https://synthetic.news.org/city/",
              "https://baltimoresun.com/news"
            )
            yaml_cased = synthetic_yaml_template.sub(
              "https://synthetic.news.org/city/",
              "  HTTPS://BALTIMORESUN.COM/news  "
            )

            file1 = File.join(dir1, "synthetic-maryland-united_states.yml")
            file2 = File.join(dir2, "synthetic-maryland-united_states.yml")
            File.write(file1, yaml_clean)
            File.write(file2, yaml_cased)

            doc1 = described_class.read(file1)
            doc2 = described_class.read(file2)

            expect(doc1.source_config_digest).to eq(doc2.source_config_digest)
          end
        end
      end

      it "rejects URLs targeting .home and .localdomain local or private destinations" do
        Dir.mktmpdir do |dir|
          [
            "https://news.localdomain/articles",
            "https://intranet.localdomain/",
            "https://gateway.localdomain",
            "https://sub.sub.localdomain/news",
            "https://news.home/articles",
            "https://router.home/",
            "https://myrouter.home",
            "https://sub.sub.home/feed",
            "https://ROUTER.HOME/admin",
            "https://News.LocalDomain/articles"
          ].each do |bad_url|
            yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", bad_url)
            file = File.join(dir, "synthetic-maryland-united_states.yml")
            File.write(file, yaml)

            expect { described_class.read(file) }
              .to raise_error(described_class::ValidationError, /url must not target a local or private destination/)
          end
        end
      end

      it "accepts legitimate public newsroom domains containing local/private keywords as substrings" do
        Dir.mktmpdir do |dir|
          [
            "https://thehomenews.org/city/",
            "https://home.com/politics/",
            "https://localdomain.com/news/",
            "https://lan.org/news/",
            "https://internal-affairs.com/investigations/"
          ].each do |valid_url|
            yaml = synthetic_yaml_template.sub("https://synthetic.news.org/city/", valid_url)
            file = File.join(dir, "synthetic-maryland-united_states.yml")
            File.write(file, yaml)

            doc = described_class.read(file)
            expect(doc.news_sources.first["url"]).to eq(valid_url)
          end
        end
      end

      it "rejects duplicate URLs differing only by explicit default port 443" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template + "  - url: \"https://synthetic.news.org:443/city/\"\n    path_policy: search_hint\n"
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Duplicate news source URL/)
        end
      end

      it "rejects duplicate URLs differing only by root domain trailing slash" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template + "  - url: \"https://rootnews.org\"\n    path_policy: search_hint\n  - url: \"https://rootnews.org/\"\n    path_policy: search_hint\n"
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Duplicate news source URL/)
        end
      end

      it "rejects duplicate URLs differing by both explicit port 443 and root trailing slash" do
        Dir.mktmpdir do |dir|
          yaml = synthetic_yaml_template + "  - url: \"https://rootnews.org:443\"\n    path_policy: search_hint\n  - url: \"https://rootnews.org/\"\n    path_policy: search_hint\n"
          file = File.join(dir, "synthetic-maryland-united_states.yml")
          File.write(file, yaml)

          expect { described_class.read(file) }
            .to raise_error(described_class::ValidationError, /Duplicate news source URL/)
        end
      end

      it "produces identical source_config_digest between explicit port 443 and implicit default port" do
        Dir.mktmpdir do |dir1|
          Dir.mktmpdir do |dir2|
            yaml_explicit = synthetic_yaml_template.sub(
              "https://synthetic.news.org/city/",
              "https://synthetic.news.org:443/city/"
            )
            yaml_implicit = synthetic_yaml_template

            file1 = File.join(dir1, "synthetic-maryland-united_states.yml")
            file2 = File.join(dir2, "synthetic-maryland-united_states.yml")
            File.write(file1, yaml_explicit)
            File.write(file2, yaml_implicit)

            doc1 = described_class.read(file1)
            doc2 = described_class.read(file2)

            expect(doc1.source_config_digest).to eq(doc2.source_config_digest)
            expect(doc1.news_sources.first["url"]).to eq("https://synthetic.news.org/city/")
          end
        end
      end

      it "produces identical source_config_digest between root domain with and without trailing slash" do
        Dir.mktmpdir do |dir1|
          Dir.mktmpdir do |dir2|
            yaml_no_slash = synthetic_yaml_template.sub(
              "https://synthetic.news.org/city/",
              "https://synthetic.news.org"
            )
            yaml_with_slash = synthetic_yaml_template.sub(
              "https://synthetic.news.org/city/",
              "https://synthetic.news.org/"
            )

            file1 = File.join(dir1, "synthetic-maryland-united_states.yml")
            file2 = File.join(dir2, "synthetic-maryland-united_states.yml")
            File.write(file1, yaml_no_slash)
            File.write(file2, yaml_with_slash)

            doc1 = described_class.read(file1)
            doc2 = described_class.read(file2)

            expect(doc1.source_config_digest).to eq(doc2.source_config_digest)
            expect(doc1.news_sources.first["url"]).to eq("https://synthetic.news.org/")
            expect(doc2.news_sources.first["url"]).to eq("https://synthetic.news.org/")
          end
        end
      end

      describe ".normalize_news_source_url" do
        it "normalizes away explicit port 443" do
          expect(described_class.normalize_news_source_url("https://example.com:443/news"))
            .to eq("https://example.com/news")
          expect(described_class.normalize_news_source_url("https://example.com:0443/news"))
            .to eq("https://example.com/news")
        end

        it "canonicalizes root domain empty path to /" do
          expect(described_class.normalize_news_source_url("https://example.com"))
            .to eq("https://example.com/")
          expect(described_class.normalize_news_source_url("https://example.com/"))
            .to eq("https://example.com/")
          expect(described_class.normalize_news_source_url("https://example.com:443"))
            .to eq("https://example.com/")
          expect(described_class.normalize_news_source_url("https://example.com:443/"))
            .to eq("https://example.com/")
        end

        it "canonicalizes root domain with query or fragment to /?query and /#frag" do
          expect(described_class.normalize_news_source_url("https://example.com?sort=desc"))
            .to eq("https://example.com/?sort=desc")
          expect(described_class.normalize_news_source_url("https://example.com#top"))
            .to eq("https://example.com/#top")
          expect(described_class.normalize_news_source_url("https://example.com:443?sort=desc#top"))
            .to eq("https://example.com/?sort=desc#top")
        end

        it "preserves non-root paths and their trailing slashes without alterations" do
          expect(described_class.normalize_news_source_url("https://example.com/news"))
            .to eq("https://example.com/news")
          expect(described_class.normalize_news_source_url("https://example.com/news/"))
            .to eq("https://example.com/news/")
        end

        it "preserves custom ports for validation rejection" do
          expect(described_class.normalize_news_source_url("https://example.com:8443/news"))
            .to eq("https://example.com:8443/news")
        end

        it "computes an identical source_config_digest regardless of YAML key ordering inside news_sources" do
          raw_yaml = File.read(described_class.default_directory.join("baltimore-maryland-united_states.yml"))
          yaml_a = YAML.safe_load(raw_yaml, permitted_classes: [Date, Time])
          yaml_b = YAML.safe_load(raw_yaml, permitted_classes: [Date, Time])
          yaml_b["news_sources"] = yaml_b["news_sources"].map do |entry|
            {"path_policy" => entry["path_policy"], "url" => entry["url"]}
          end

          Dir.mktmpdir do |dir1|
            Dir.mktmpdir do |dir2|
              file1 = File.join(dir1, "baltimore-maryland-united_states.yml")
              file2 = File.join(dir2, "baltimore-maryland-united_states.yml")
              File.write(file1, YAML.dump(yaml_a))
              File.write(file2, YAML.dump(yaml_b))

              doc_a = described_class.read(file1)
              doc_b = described_class.read(file2)

              expect(doc_a.source_config_digest).to eq(doc_b.source_config_digest)
            end
          end
        end
      end

      # @lat: [[locale-extension#Legislative session schema and validations]]
      describe "YAML alias and identity mismatch guards" do
        it "rejects YAML anchors and aliases with ValidationError" do
          raw_yaml = File.read(described_class.default_directory.join("baltimore-maryland-united_states.yml"))
          aliased_yaml = "#{raw_yaml}\nanchor_test: &anc\n  key: val\nalias_test:\n  <<: *anc\n"

          Dir.mktmpdir do |dir|
            path = Pathname.new(dir).join("baltimore-maryland-united_states.yml")
            path.write(aliased_yaml)

            expect {
              described_class.read(path)
            }.to raise_error(described_class::ValidationError, /YAML aliases are not allowed/)
          end
        end

        it "rejects a document whose declared name does not match its normalized city/state/country tuple" do
          raw_yaml = File.read(described_class.default_directory.join("baltimore-maryland-united_states.yml"))
          yaml = YAML.safe_load(raw_yaml, permitted_classes: [Date, Time])
          yaml["name"] = "wrong-name-tuple"

          Dir.mktmpdir do |dir|
            file = File.join(dir, "baltimore-maryland-united_states.yml")
            File.write(file, YAML.dump(yaml))

            expect {
              described_class.read(file)
            }.to raise_error(described_class::ValidationError, /Declared name .* does not match normalized identity/)
          end
        end
      end
    end
  end
end
