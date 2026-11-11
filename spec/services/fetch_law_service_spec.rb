# frozen_string_literal: true

require "rails_helper"

# Specs for FetchLawService. Helper paths and constants live on a frozen
# module, not `let(...)`, since Steep can't see through RSpec's DSL (same
# approach as fetch_bills_service_spec.rb).
module FetchLawServiceSpecHelpers
  TMP_LAW_ROOT = LegislationTestArtifacts.root_for("fetch_law_service").freeze

  # Builds the smallest usable Akoma Ntoso document (the legal-text XML
  # standard) matching the real corpus. container_num names the article, so
  # fixtures produce different keys.
  def self.minimal_law_xml(container_num:, sections:)
    section_xml = sections.map { |s|
      "      <section><num>#{s[:num]}</num><heading>#{s[:heading]}</heading><text>#{s[:text]}</text></section>"
    }.join("\n")
    <<~XML
      <?xml version='1.0' encoding='utf-8'?>
      <document xmlns="https://open.law/schemas/library">
        <container>
          <num>#{container_num}</num>
          <heading>General</heading>
      #{section_xml}
        </container>
      </document>
    XML
  end

  def self.minimal_charter_xml(sections:)
    minimal_law_xml(container_num: "I", sections: sections)
  end

  def self.baltimore_raw_dir
    Pathname.new(TMP_LAW_ROOT).join("raw", "law-xml-main", "us", "md", "cities", "baltimore")
  end

  def self.write_raw_charter(content)
    baltimore_raw_dir.mkpath
    baltimore_raw_dir.join("charter.xml").write(content)
  end

  # Write one article of the Code as XML under the baltimore code/ directory. The
  # real corpus has no single code.xml; it splits the Code into code/8.xml,
  # code/health.xml, and so on.
  def self.write_raw_code(filename, content)
    code_dir = baltimore_raw_dir.join("code")
    code_dir.mkpath
    code_dir.join(filename).write(content)
  end
end

RSpec.describe FetchLawService do
  let(:run) { instance_double(LegislationPipelineRun, id: 7) }
  let!(:baltimore) { SwayLocale.find_by(city: "baltimore") || create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states") }

  around do |example|
    FileUtils.rm_rf(FetchLawServiceSpecHelpers::TMP_LAW_ROOT)
    FileUtils.mkdir_p(FetchLawServiceSpecHelpers::TMP_LAW_ROOT)
    with_app_config(:legislation, legislation_law_root: FetchLawServiceSpecHelpers::TMP_LAW_ROOT) { example.run }
  ensure
    FileUtils.rm_rf(FetchLawServiceSpecHelpers::TMP_LAW_ROOT)
  end

  before do
    # #call downloads/refreshes the corpus via FetchLawCorpusService
    # first. These specs put charter.xml on disk directly, so that fetch is
    # stubbed to do nothing (the downloader has its own specs).
    allow(FetchLawCorpusService).to receive(:new)
      .and_return(instance_double(FetchLawCorpusService, call: :unchanged))
  end

  # The fallback lookup used find_by(name:), but `name` is computed, not a
  # real column — a miss on the main lookup raised StatementInvalid instead
  # of the intended StageError.
  describe "#resolve_sway_locale" do
    it "resolves the default SwayLocale via computed name fallback" do
      SwayLocale.where(city: "baltimore").destroy_all
      # nameify cleans the record up ON SAVE (city/state become lowercase), so
      # the computed name matches LegislationIngestionService::DEFAULT_LOCALE_NAME.
      create(:sway_locale, city: "Baltimore", state: "MD", country: "United States")
      expect(SwayLocale.resolve_by_computed_name(LegislationIngestionService::DEFAULT_LOCALE_NAME)).to be_present

      expect { described_class.new(run: run) }.not_to raise_error
    end

    it "raises StageError (not StatementInvalid) when no default locale exists — exercises the fallback" do
      # With no match, resolve_sway_locale falls through to resolve_by_computed_name,
      # which now raises the intended StageError instead of StatementInvalid
      # from the old fallback's nonexistent column.
      SwayLocale.where(city: "baltimore").destroy_all

      expect { described_class.new(run: run) }
        .to raise_error(StageError, /no default SwayLocale/)
    end
  end

  describe "#call — happy path against a fixture charter.xml" do
    it "upserts LawSection rows, writes per-section .md files, and emits section_index.json" do
      FetchLawServiceSpecHelpers.write_raw_charter(
        FetchLawServiceSpecHelpers.minimal_charter_xml(sections: [
          {num: "1", heading: "Powers", text: "All powers shall vest."},
          {num: "2", heading: "Duties", text: "Duties of the council."}
        ])
      )

      stats = described_class.new(run: run).call

      expect(stats["sections_upserted"]).to eq(2)
      expect(stats["files_written"]).to eq(2)
      expect(stats["articles_processed"]).to eq(1)

      sections = LawSection.where(sway_locale: baltimore).order(:key)
      expect(sections.pluck(:key)).to contain_exactly("art_I__sec_1", "art_I__sec_2")
      first = LawSection.find_by!(sway_locale: baltimore, key: "art_I__sec_1")
      expect(first.title).to eq("Powers")
      expect(first.article).to eq("General")
      expect(first.source_path).to eq("charter/art-I/sec-1.md")

      law_root = Pathname.new(FetchLawServiceSpecHelpers::TMP_LAW_ROOT)
      expect(law_root.join("charter/art-I/sec-1.md").exist?).to be(true)
      expect(law_root.join("charter/art-I/sec-2.md").exist?).to be(true)

      index = JSON.parse(law_root.join("section_index.json").read)
      expect(index.keys.sort).to eq(%w[art_I__sec_1 art_I__sec_2])
      expect(index["art_I__sec_1"]).to include("path" => "charter/art-I/sec-1.md", "status" => "active")
    end
  end

  describe "#call — ingests the multi-file Code corpus" do
    it "parses every code/*.xml (not a single code.xml) and scopes its sections under code/" do
      FetchLawServiceSpecHelpers.write_raw_charter(
        FetchLawServiceSpecHelpers.minimal_charter_xml(sections: [
          {num: "1", heading: "Powers", text: "Charter section."}
        ])
      )
      FetchLawServiceSpecHelpers.write_raw_code(
        "8.xml",
        FetchLawServiceSpecHelpers.minimal_law_xml(container_num: "8", sections: [
          {num: "1", heading: "Zoning", text: "Code article 8."}
        ])
      )
      FetchLawServiceSpecHelpers.write_raw_code(
        "health.xml",
        FetchLawServiceSpecHelpers.minimal_law_xml(container_num: "9", sections: [
          {num: "1", heading: "Sanitation", text: "Health code."}
        ])
      )

      stats = described_class.new(run: run).call

      # 1 charter article plus 2 code articles, all ingested. Before the fix the
      # entire Code was dropped without a word, because locate_xml("code.xml")
      # matched nothing.
      expect(stats["articles_processed"]).to eq(3)
      expect(stats["sections_upserted"]).to eq(3)

      index = JSON.parse(Pathname.new(FetchLawServiceSpecHelpers::TMP_LAW_ROOT).join("section_index.json").read)
      paths = index.values.pluck("path")
      expect(paths.count { |p| p.start_with?("charter/") }).to eq(1)
      expect(paths.count { |p| p.start_with?("code/") }).to eq(2)
      expect(LawSection.where(sway_locale: baltimore).count).to eq(3)
    end
  end

  describe "#call — idempotent re-run" do
    it "does not duplicate LawSection rows across two invocations" do
      FetchLawServiceSpecHelpers.write_raw_charter(
        FetchLawServiceSpecHelpers.minimal_charter_xml(sections: [
          {num: "1", heading: "Powers", text: "Run one."}
        ])
      )

      described_class.new(run: run).call
      first_count = LawSection.where(sway_locale: baltimore).count
      first_updated_at = LawSection.find_by!(sway_locale: baltimore, key: "art_I__sec_1").updated_at

      sleep(0.01)
      # Change the body so the second run actually updates the row.
      FetchLawServiceSpecHelpers.write_raw_charter(
        FetchLawServiceSpecHelpers.minimal_charter_xml(sections: [
          {num: "1", heading: "Powers", text: "Run two."}
        ])
      )
      described_class.new(run: run).call

      expect(LawSection.where(sway_locale: baltimore).count).to eq(first_count)
      row = LawSection.find_by!(sway_locale: baltimore, key: "art_I__sec_1")
      expect(row.body).to include("Run two.")
      expect(row.updated_at).to be > first_updated_at
    end
  end

  describe "#call — locale scoping (Pitfall 5)" do
    it "scopes LawSection rows by sway_locale_id" do
      maryland = create(:sway_locale, city: "annapolis", state: "MD", country: "united_states")
      LawSection.create!(
        sway_locale: maryland,
        key: "art_I__sec_1",
        article: "Other",
        section: "1",
        title: "Other locale row",
        body: "Body",
        source_path: "other/sec.md"
      )

      FetchLawServiceSpecHelpers.write_raw_charter(
        FetchLawServiceSpecHelpers.minimal_charter_xml(sections: [
          {num: "1", heading: "Powers", text: "Baltimore powers."}
        ])
      )
      described_class.new(run: run).call

      baltimore_row = LawSection.find_by!(sway_locale: baltimore, key: "art_I__sec_1")
      maryland_row = LawSection.find_by!(sway_locale: maryland, key: "art_I__sec_1")

      expect(baltimore_row.body).to include("Baltimore powers.")
      expect(maryland_row.body).to eq("Body")
    end
  end

  describe "#call — detect_status classification in section_index" do
    it "maps Reserved/Repealed/active titles correctly" do
      FetchLawServiceSpecHelpers.write_raw_charter(
        FetchLawServiceSpecHelpers.minimal_charter_xml(sections: [
          {num: "1", heading: "Powers", text: "Normal active section."},
          {num: "2", heading: "Reserved for future use", text: ""},
          {num: "3", heading: "Repealed by Ord. 12", text: ""}
        ])
      )

      described_class.new(run: run).call

      index = JSON.parse(Pathname.new(FetchLawServiceSpecHelpers::TMP_LAW_ROOT).join("section_index.json").read)
      expect(index["art_I__sec_1"]["status"]).to eq("active")
      expect(index["art_I__sec_2"]["status"]).to eq("reserved")
      expect(index["art_I__sec_3"]["status"]).to eq("repealed")
    end
  end

  describe "#call — malformed XML" do
    it "raises StageError with truncated message" do
      raw_dir = Pathname.new(FetchLawServiceSpecHelpers::TMP_LAW_ROOT).join("raw")
      raw_dir.mkpath
      raw_dir.join("charter.xml").write("<not-well-formed><unclosed>")

      expect { described_class.new(run: run).call }.to raise_error(StageError, /malformed XML/)
    end
  end

  describe "#call — missing charter.xml" do
    it "raises StageError with the missing-file message" do
      # No charter.xml written.
      expect { described_class.new(run: run).call }.to raise_error(StageError, /missing charter\.xml/)
    end
  end

  describe "#call — non-Baltimore jurisdiction rules" do
    let(:maryland_locale) { create(:sway_locale, :maryland) }
    let(:maryland_run) { create(:legislation_pipeline_run, sway_locale: maryland_locale) }

    # @lat: [[legislation-pipeline#The legislation pipeline#Maryland PDF law corpus acquisition#Fetches and parses Maryland Code when the local corpus is absent]]
    it "acquires and parses Maryland statute PDFs when its local corpus is missing" do
      raw_dir = Legislation::Paths.law(sway_locale: maryland_locale).join("raw")
      catalog_url = "https://mgaleg.maryland.gov/mgawebsite/api/Laws/GetArticles"
      article_link_url = "https://mgaleg.maryland.gov/mgawebsite/api/Laws/GetArticleLink"
      pdf_url = "https://mgaleg.maryland.gov/2027RS/Statute_Web/gag/gag.pdf"
      extracted_text = <<~TEXT
        GENERAL PROVISIONS
        § 1–101. Definitions.
        In this article, the following words have the meanings indicated.
      TEXT
      extractor = instance_double(MupdfExtractor, call: extracted_text)
      allow(MupdfExtractor).to receive(:new).with(raw_dir.join("gag.pdf").to_s).and_return(extractor)
      stub_request(:get, catalog_url)
        .with(query: {"enactments" => "true"})
        .to_return(status: 200, body: JSON.generate([{"DisplayText" => "General Provisions", "Value" => "gag"}]))
      stub_request(:get, article_link_url)
        .with(query: {"articleCode" => "gag", "enactments" => "true"})
        .to_return(status: 200, body: JSON.generate(pdf_url))
      stub_request(:get, pdf_url).to_return(status: 200, body: "%PDF-1.7\nsynthetic statute bytes")

      stats = described_class.new(run: maryland_run).call

      expect(stats).to include("sections_upserted" => 1, "articles_processed" => 1)
      expect(raw_dir.join("gag.pdf").read).to start_with("%PDF-")
      expect(LawSection.find_by!(sway_locale: maryland_locale, key: "art_gag__sec_1-101")).to have_attributes(
        article: "gag",
        section: "1-101",
        title: "Definitions",
        body: "In this article, the following words have the meanings indicated."
      )
      expect(WebMock).to have_requested(:get, pdf_url).once
    end

    it "never invokes FetchLawCorpusService for non-Baltimore locales" do
      allow(FetchLawCorpusService).to receive(:new)
      allow(Legislation::RemotePdfLawCorpusService).to receive(:new)
        .and_return(instance_double(Legislation::RemotePdfLawCorpusService, call: :cached_offline))
      begin
        described_class.new(run: maryland_run).call
      rescue StageError
        nil
      end

      expect(FetchLawCorpusService).not_to have_received(:new)
    end
  end

  describe "Declare unavailable law acquisition for manual locales" do
    it "raises StageError reporting that law acquisition is unavailable for the locale" do
      manual_rules = instance_double(
        SwayLocale::JurisdictionRules,
        law_rules: {engine: :unavailable}
      )
      manual_locale = instance_double(
        SwayLocale,
        name: "manual-locale-united_states",
        jurisdiction_rules: manual_rules
      )
      manual_run = instance_double(LegislationPipelineRun, id: 99, effective_sway_locale: manual_locale)
      service = described_class.new(run: manual_run)
      expect { service.call }.to raise_error(
        StageError,
        "fetch_law: law acquisition is unavailable for manual-locale-united_states"
      )
    end

    it "does not raise unavailable error when law_rules is configured even if legacy law_source is :unavailable" do
      rules = double("JurisdictionRules", law_rules: {engine: :generic_xml}, law_source: :unavailable)
      locale = instance_double(
        SwayLocale,
        name: "configured-locale",
        jurisdiction_rules: rules
      )
      run = instance_double(LegislationPipelineRun, id: 101, effective_sway_locale: locale)
      service = described_class.new(run: run)
      allow(Legislation::Paths).to receive(:law).and_return(Pathname.new("/tmp/test_law"))
      allow_any_instance_of(Legislation::Adapters::GenericLawAdapter).to receive(:load_corpus)
        .and_return({"sections_upserted" => 0, "files_written" => 0, "articles_processed" => 0})

      expect { service.call }.not_to raise_error
    end
  end
end
