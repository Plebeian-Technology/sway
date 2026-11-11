# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legislation::Adapters::GenericLawAdapter do
  let(:maryland) { create(:sway_locale, :maryland) }
  let(:xml_fixture) do
    <<~XML
      <laws>
        <article name="Transportation">
          <section number="21-801" title="Speed limits">
            <body>An individual may not drive a vehicle on a highway at a speed greater than reasonable.</body>
          </section>
        </article>
      </laws>
    XML
  end

  around do |example|
    Dir.mktmpdir("generic_law_spec") do |tmp|
      @tmp_root = Pathname.new(tmp)
      example.run
    end
  end

  before do
    allow(Legislation::Paths).to receive(:root).and_return(@tmp_root) if @tmp_root
  end

  describe "initialization" do
    it "initializes from raw config hash" do
      adapter = described_class.new({engine: "generic_xml", base_url: "https://example.gov"})
      expect(adapter.engine).to eq(:generic_xml)
      expect(adapter.base_url).to eq("https://example.gov")
    end

    it "initializes from SwayLocale instance" do
      adapter = described_class.new(maryland)
      expect(adapter.engine).to eq(:configured_pdf_catalog)
      expect(adapter.parsing).to eq(:pdf_statute_sections)

      baltimore = create(:sway_locale, :baltimore)
      expect(described_class.new(baltimore).engine).to eq(:akoma_ntoso)

      congress = create(:sway_locale, :congress)
      expect(described_class.new(congress).engine).to eq(:uslm_xml)
    end

    it "initializes from keyword arguments" do
      adapter = described_class.new(retrieval: :local_raw, parsing: :generic_xml)
      expect(adapter.retrieval).to eq(:local_raw)
      expect(adapter.parsing).to eq(:generic_xml)
    end

    it "preserves locale rules and merges keyword arguments when initialized with SwayLocale and kwargs" do
      adapter = described_class.new(maryland, extra_option: "something", custom_timeout: 30)
      expect(adapter.retrieval).to eq(:configured_pdf_catalog)
      expect(adapter.parsing).to eq(:pdf_statute_sections)
      expect(adapter.config[:extra_option]).to eq("something")
      expect(adapter.config[:custom_timeout]).to eq(30)
      expect(adapter.instance_variable_get(:@sway_locale)).to eq(maryland)
    end

    it "preserves rules and merges keyword arguments when initialized with a duck-typed jurisdiction_rules object" do
      fake_conn = instance_double(Faraday::Connection)
      duck_rules = instance_double(
        SwayLocale::JurisdictionRules,
        law_rules: {retrieval: "uslm_xml", parsing: "uslm_xml"},
        law_retrieval: "uslm_xml",
        law_parsing: "uslm_xml"
      )
      duck_locale = double("DuckLocale", jurisdiction_rules: duck_rules)
      adapter = described_class.new(duck_locale, connection: fake_conn, git_branch: "master", extra_flag: 42)
      expect(adapter.retrieval).to eq(:uslm_xml)
      expect(adapter.parsing).to eq(:uslm_xml)
      expect(adapter.connection).to eq(fake_conn)
      expect(adapter.config[:git_branch]).to eq("master")
      expect(adapter.config[:extra_flag]).to eq(42)
    end

    it "preserves rules and merges keyword arguments when initialized with an object responding directly to law_rules" do
      fake_conn = instance_double(Faraday::Connection)
      duck_mock = double("DirectLawRulesMock", law_rules: {retrieval: "local_raw", parsing: "generic_xml"})
      adapter = described_class.new(duck_mock, connection: fake_conn, extra_param: 42)
      expect(adapter.retrieval).to eq(:local_raw)
      expect(adapter.parsing).to eq(:generic_xml)
      expect(adapter.connection).to eq(fake_conn)
      expect(adapter.config[:extra_param]).to eq(42)
    end

    it "allows keyword arguments to override specific extracted rules while preserving the rest" do
      adapter = described_class.new(maryland, retrieval: :filesystem)
      expect(adapter.retrieval).to eq(:filesystem)
      expect(adapter.parsing).to eq(:pdf_statute_sections)
      expect(adapter.instance_variable_get(:@sway_locale)).to eq(maryland)
    end
  end

  describe "#load_corpus with raw XML and JSON" do
    let(:law_root) { @tmp_root.join("legislation", maryland.name, "law") }

    before do
      @json_fixture = {
        article: "Education",
        sections: [
          {
            number: "7-101",
            title: "Admission of students",
            body: "All individuals between the ages of 5 and 21 shall be admitted free of charge."
          }
        ]
      }.to_json
      raw_dir = law_root.join("raw")
      FileUtils.mkdir_p(raw_dir)
      File.write(raw_dir.join("transportation.xml"), xml_fixture)
      File.write(raw_dir.join("education.json"), @json_fixture)
    end

    it "parses sections, upserts database records, writes markdown, and returns stats" do
      adapter = described_class.new({engine: "generic_xml"})

      stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)

      expect(stats["sections_upserted"]).to eq(2)
      expect(stats["files_written"]).to eq(2)
      expect(stats["articles_processed"]).to eq(2)

      # Check files written
      expect(law_root.join("code/Transportation/21-801.md")).to exist
      expect(law_root.join("code/Education/7-101.md")).to exist

      # Check index file written
      index_file = Legislation::Paths.law_section_index_file(sway_locale: maryland)
      expect(index_file).to exist
      index = JSON.parse(index_file.read)
      expect(index).to have_key("art_Transportation__sec_21-801")
      expect(index).to have_key("art_Education__sec_7-101")
    end

    it "raises StageError when raw corpus directory is missing" do
      missing_root = @tmp_root.join("nonexistent_law_root")
      adapter = described_class.new({engine: "generic_xml"})

      expect {
        adapter.load_corpus(run: nil, sway_locale: maryland, law_root: missing_root)
      }.to raise_error(StageError, /missing #{maryland.name} law corpus/)
    end

    it "raises StageError when raw corpus directory contains no files" do
      empty_root = @tmp_root.join("empty_law_root")
      FileUtils.mkdir_p(empty_root.join("raw"))
      adapter = described_class.new({engine: "generic_xml"})

      expect {
        adapter.load_corpus(run: nil, sway_locale: maryland, law_root: empty_root)
      }.to raise_error(StageError, /missing #{maryland.name} law corpus/)
    end

    context "with empty or invalid sections" do
      it "skips sections with empty body in XML without crashing and logs warning" do
        xml_with_empty_body = <<~XML
          <laws>
            <article name="Transportation">
              <section number="21-801" title="Valid speed limits">
                <body>Valid speed limit body.</body>
              </section>
              <section number="21-802" title="Repealed section">
                <body>   </body>
              </section>
            </article>
          </laws>
        XML
        File.write(law_root.join("raw", "transportation.xml"), xml_with_empty_body)
        FileUtils.rm_f(law_root.join("raw", "education.json"))

        adapter = described_class.new({engine: "generic_xml"})
        allow(SwayLogging).to receive(:warn)

        stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)

        expect(stats["sections_upserted"]).to eq(1)
        expect(stats["files_written"]).to eq(1)
        expect(law_root.join("code/Transportation/21-801.md")).to exist
        expect(law_root.join("code/Transportation/21-802.md")).not_to exist
        expect(SwayLogging).to have_received(:warn).with(/skipping section with blank number or body/)
      end

      it "skips sections with missing section number in XML without crashing" do
        xml_missing_number = <<~XML
          <laws>
            <article name="Transportation">
              <section number="21-801" title="Valid">
                <body>Valid speed limit body.</body>
              </section>
              <section title="No Number">
                <body>Some body text without section number.</body>
              </section>
            </article>
          </laws>
        XML
        File.write(law_root.join("raw", "transportation.xml"), xml_missing_number)
        FileUtils.rm_f(law_root.join("raw", "education.json"))

        adapter = described_class.new({engine: "generic_xml"})
        allow(SwayLogging).to receive(:warn)

        stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)

        expect(stats["sections_upserted"]).to eq(1)
        expect(SwayLogging).to have_received(:warn).with(/skipping section with blank number or body/)
      end

      it "skips sections with empty body or blank number in JSON without crashing" do
        FileUtils.rm_f(law_root.join("raw", "transportation.xml"))
        mixed_json = {
          article: "Education",
          sections: [
            {number: "7-101", title: "Valid", body: "Valid education law."},
            {number: "7-102", title: "Empty body", body: ""},
            {number: nil, title: "No number", body: "Missing number."}
          ]
        }.to_json
        File.write(law_root.join("raw", "education.json"), mixed_json)

        adapter = described_class.new({engine: "generic_xml"})
        allow(SwayLogging).to receive(:warn)

        stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)

        expect(stats["sections_upserted"]).to eq(1)
        expect(stats["files_written"]).to eq(1)
        expect(law_root.join("code/Education/7-101.md")).to exist
        expect(law_root.join("code/Education/7-102.md")).not_to exist
        expect(SwayLogging).to have_received(:warn).with(/skipping section with blank number or body/).twice
      end

      it "rescues ActiveRecord::RecordInvalid during section upsert and logs warning" do
        FileUtils.rm_f(law_root.join("raw", "transportation.xml"))
        File.write(law_root.join("raw", "education.json"), @json_fixture)

        adapter = described_class.new({engine: "generic_xml"})
        allow(FetchLawService::LawSectionUpsert).to receive(:call).and_raise(
          ActiveRecord::RecordInvalid.new(LawSection.new)
        )
        allow(SwayLogging).to receive(:warn)

        expect {
          adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)
        }.to raise_error(StageError, /statutory law corpus contains no sections/)

        expect(SwayLogging).to have_received(:warn).with(/validation failed for section/)
      end
    end

    describe "XML parser security" do
      it "disables network access during XML parsing (nonet)" do
        xml_path = law_root.join("raw", "transportation.xml")
        adapter = described_class.new({engine: "generic_xml"})

        xxe_xml = <<~XML
          <?xml version="1.0"?>
          <!DOCTYPE laws [
            <!ENTITY xxe SYSTEM "http://127.0.0.1:9999/xxe">
          ]>
          <laws>
            <article name="Transportation">
              <section number="21-801" title="Speed">
                <body>&xxe;</body>
              </section>
            </article>
          </laws>
        XML
        File.write(xml_path, xxe_xml)
        FileUtils.rm_f(law_root.join("raw", "education.json"))

        expect {
          adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)
        }.to raise_error(StageError, /statutory law corpus contains no sections/)
      end
    end
  end

  describe "#load_corpus with a PDF statute corpus" do
    # @lat: [[legislation-pipeline#The legislation pipeline#Maryland PDF law corpus acquisition#Parses article PDFs into locale-scoped law sections]]
    it "extracts Maryland article sections and writes locale-scoped records and index entries" do
      law_root = Legislation::Paths.law(sway_locale: maryland)
      raw_dir = law_root.join("raw")
      raw_dir.mkpath
      pdf_path = raw_dir.join("gag.pdf")
      pdf_path.write("%PDF-1.4\n")

      extracted_text = <<~TEXT
        GENERAL PROVISIONS
        § 1–101. Definitions.
        In this article, the following words have the meanings indicated.

        § 1—102. Scope.
        This article applies throughout the State.
      TEXT
      extractor = instance_double(MupdfExtractor, call: extracted_text)
      expect(MupdfExtractor).to receive(:new).with(pdf_path.to_s).and_return(extractor)

      other_locale = create(:sway_locale, :baltimore)
      other_locale_section = create(:law_section,
        sway_locale: other_locale,
        key: "art_gag__sec_1-101",
        article: "gag",
        section: "1-101",
        title: "Other locale",
        body: "Other locale text remains unchanged.",
        source_path: "code/gag/1-101.md")
      adapter = described_class.new({retrieval: :local_raw, parsing: :pdf_statute_sections, local_path: "raw"})
      stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)

      expect(stats).to include("sections_upserted" => 2, "articles_processed" => 1)
      expect(LawSection.find_by!(sway_locale: maryland, key: "art_gag__sec_1-101")).to have_attributes(
        article: "gag",
        section: "1-101",
        title: "Definitions",
        body: "In this article, the following words have the meanings indicated."
      )
      expect(LawSection.find_by!(sway_locale: maryland, key: "art_gag__sec_1-102")).to have_attributes(
        article: "gag",
        section: "1-102",
        title: "Scope",
        body: "This article applies throughout the State."
      )

      index = JSON.parse(Legislation::Paths.law_section_index_file(sway_locale: maryland).read)
      expect(index.fetch("art_gag__sec_1-101")).to include(
        "path" => "code/gag/1-101.md",
        "article" => "gag",
        "title" => "Definitions"
      )
      expect(LawSection.find_by!(sway_locale: other_locale, key: "art_gag__sec_1-101"))
        .to have_attributes(id: other_locale_section.id, body: "Other locale text remains unchanged.")
    end

    it "parses repealed sections with single status lines, inline headings, and structural dividers in gab.pdf" do
      law_root = Legislation::Paths.law(sway_locale: maryland)
      raw_dir = law_root.join("raw")
      raw_dir.mkpath
      pdf_path = raw_dir.join("gab.pdf")
      pdf_path.write("%PDF-1.4\n")

      extracted_text = <<~TEXT
        Title 1. Definitions; General Provisions.
        Subtitle 1. Definitions.
        § 1–101. Definitions.
        In this article, the following words have the meanings indicated.

        § 1–201.
        Repealed by Acts 2024, ch. 1, § 2.

        Title 2. Commercial Law.
        Subtitle 1. Licenses.
        Part I. General Provisions.
        § 2–101. Scope of title.
        This title applies to commercial licenses.
      TEXT

      extractor = instance_double(MupdfExtractor, call: extracted_text)
      expect(MupdfExtractor).to receive(:new).with(pdf_path.to_s).and_return(extractor)

      adapter = described_class.new({retrieval: :local_raw, parsing: :pdf_statute_sections, local_path: "raw"})
      stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)

      expect(stats).to include("sections_upserted" => 3, "articles_processed" => 1)
      sec1 = LawSection.find_by!(sway_locale: maryland, key: "art_gab__sec_1-101")
      expect(sec1.title).to eq("Definitions")
      expect(sec1.body).to eq("In this article, the following words have the meanings indicated.")

      sec2 = LawSection.find_by!(sway_locale: maryland, key: "art_gab__sec_1-201")
      expect(sec2.title).to eq("Repealed by Acts 2024, ch. 1, § 2")
      expect(sec2.body).to eq("Repealed by Acts 2024, ch. 1, § 2")

      sec3 = LawSection.find_by!(sway_locale: maryland, key: "art_gab__sec_2-101")
      expect(sec3.title).to eq("Scope of title")
      expect(sec3.body).to eq("This title applies to commercial licenses.")
    end

    it "raises when a PDF contains an incomplete statutory section without heading or body" do
      law_root = Legislation::Paths.law(sway_locale: maryland)
      raw_dir = law_root.join("raw")
      raw_dir.mkpath
      pdf_path = raw_dir.join("gab.pdf")
      pdf_path.write("%PDF-1.4\n")

      extracted_text = <<~TEXT
        § 1–101.
        § 1–102.
      TEXT

      extractor = instance_double(MupdfExtractor, call: extracted_text)
      expect(MupdfExtractor).to receive(:new).with(pdf_path.to_s).and_return(extractor)

      adapter = described_class.new({retrieval: :local_raw, parsing: :pdf_statute_sections, local_path: "raw"})
      expect { adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root) }
        .to raise_error(StageError, /fetch_law: incomplete statutory section in gab\.pdf/)
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Maryland PDF law corpus acquisition#Extracts native text and strips repeated page furniture]]
    it "extracts a local Maryland PDF fixture and omits repeated headers and page numbers" do
      law_root = Legislation::Paths.law(sway_locale: maryland)
      raw_dir = law_root.join("raw")
      raw_dir.mkpath
      FileUtils.cp(
        Rails.root.join("spec", "fixtures", "legislation", "maryland", "sample_statute.pdf"),
        raw_dir.join("gag.pdf")
      )
      adapter = described_class.new({retrieval: :local_raw, parsing: :pdf_statute_sections, local_path: "raw"})

      Dir.mktmpdir("maryland-tessdata") do |tessdata|
        FileUtils.touch(File.join(tessdata, "eng.traineddata"))
        with_app_config(:legislation, tessdata_prefix: tessdata) do
          stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)

          expect(stats).to include("sections_upserted" => 2, "articles_processed" => 1)
        end
      end

      first = LawSection.find_by!(sway_locale: maryland, key: "art_gag__sec_1-101")
      second = LawSection.find_by!(sway_locale: maryland, key: "art_gag__sec_1-102")
      expect(first.body).to eq("In this article, the following words have the meanings indicated.")
      expect(second.body).to eq("This article applies throughout the State.")
      expect([first.body, second.body].join(" ")).not_to match(/GENERAL PROVISIONS|\b[12]\b/)
    end

    it "calls configured acquisition once and parses its cache in online and offline modes" do
      law_root = Legislation::Paths.law(sway_locale: maryland)
      pdf_path = law_root.join("raw", "gag.pdf")
      pdf_path.dirname.mkpath
      pdf_path.write("%PDF-1.4\n")
      extractor = instance_double(
        MupdfExtractor,
        call: "§ 1-101. Definitions.\nThe words in this article have the meanings indicated."
      )
      expect(MupdfExtractor).to receive(:new).with(pdf_path.to_s).twice.and_return(extractor)
      acquisition = instance_double(Legislation::RemotePdfLawCorpusService)
      expect(Legislation::RemotePdfLawCorpusService).to receive(:new)
        .with(sway_locale: maryland, law_root: law_root, http: nil)
        .twice.and_return(acquisition)
      allow(acquisition).to receive(:call).and_return(:unchanged, :cached_offline)

      2.times do
        adapter = described_class.new(maryland)
        expect(adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)["sections_upserted"]).to eq(1)
      end
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Maryland PDF law corpus acquisition#Rejects malformed later articles without replacing prior sections]]
    it "rejects a malformed later article without changing rows or the published index" do
      law_root = Legislation::Paths.law(sway_locale: maryland)
      raw_dir = law_root.join("raw")
      raw_dir.mkpath
      first_pdf = raw_dir.join("gag.pdf")
      second_pdf = raw_dir.join("gbg.pdf")
      first_pdf.write("%PDF-1.4\n")
      second_pdf.write("%PDF-1.4\n")
      first_extractor = instance_double(
        MupdfExtractor,
        call: "§ 1-101. Definitions.\nFirst article body is valid."
      )
      second_extractor = instance_double(MupdfExtractor, call: "no statute sections in this article")
      allow(MupdfExtractor).to receive(:new).with(first_pdf.to_s).and_return(first_extractor)
      allow(MupdfExtractor).to receive(:new).with(second_pdf.to_s).and_return(second_extractor)

      existing = create(:law_section,
        sway_locale: maryland,
        key: "art_old__sec_1",
        article: "old",
        section: "1",
        title: "Existing",
        body: "Previously published text.",
        source_path: "code/old/1.md")
      index_file = Legislation::Paths.law_section_index_file(sway_locale: maryland)
      old_index = {"art_old__sec_1" => {"path" => existing.source_path, "article" => "old", "title" => "Existing", "status" => "active"}}
      index_file.write(JSON.generate(old_index))
      adapter = described_class.new({retrieval: :local_raw, parsing: :pdf_statute_sections, local_path: "raw"})

      expect {
        adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)
      }.to raise_error(StageError, /contains no statutory sections/)
      expect(LawSection.where(sway_locale: maryland).pluck(:key)).to eq(["art_old__sec_1"])
      expect(JSON.parse(index_file.read)).to eq(old_index)
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Maryland PDF law corpus acquisition#Parses article PDFs into locale-scoped law sections]]
    context "with real Maryland statute PDF failure modes" do
      let(:law_root) { Legislation::Paths.law(sway_locale: maryland) }
      let(:raw_dir) { law_root.join("raw") }
      let(:adapter) { described_class.new({retrieval: :local_raw, parsing: :pdf_statute_sections, local_path: "raw"}) }

      before do
        raw_dir.mkpath
      end

      it "preserves wrapped in-body section references inside an open section without raising StageError or splitting sections" do
        pdf_path = raw_dir.join("gab.pdf")
        pdf_path.write("%PDF-1.4\n")
        extracted_text = <<~TEXT
          Article - Alcoholic Beverages
          §1–101.
          (a) In this section:
          (1)
          §
          6–209
          applies to licensed premises.
          § 6–207 (“Display of license”) also applies.
          See §§ 10–614 through 10–619 for enforcement.
          §1–102.
          (a) General provisions.
        TEXT
        extractor = instance_double(MupdfExtractor, call: extracted_text)
        allow(MupdfExtractor).to receive(:new).with(pdf_path.to_s).and_return(extractor)

        stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)
        expect(stats["sections_upserted"]).to eq(2)

        sec1 = LawSection.find_by!(sway_locale: maryland, key: "art_gab__sec_1-101")
        expect(sec1.body).to include("6–209")
        expect(sec1.body).to include("§ 6–207 (“Display of license”) also applies.")
        expect(sec1.body).to include("See §§ 10–614 through 10–619 for enforcement.")
        expect(LawSection.find_by(sway_locale: maryland, key: "art_gab__sec_6-209")).to be_nil
        expect(LawSection.find_by(sway_locale: maryland, key: "art_gab__sec_6-207")).to be_nil
      end

      it "raises StageError matching /fetch_law: malformed section marker/ when a PDF contains only a malformed marker before any valid section opens" do
        pdf_path = raw_dir.join("gab.pdf")
        pdf_path.write("%PDF-1.4\n")
        extracted_text = <<~TEXT
          Article - Alcoholic Beverages
          § malformed marker without prior valid section
        TEXT
        extractor = instance_double(MupdfExtractor, call: extracted_text)
        allow(MupdfExtractor).to receive(:new).with(pdf_path.to_s).and_return(extractor)

        expect {
          adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)
        }.to raise_error(StageError, /fetch_law: malformed section marker in gab\.pdf/)
      end

      it "parses decimal title/subtitle section headers and period-less headers on their own line into ASCII hyphens" do
        pdf_path = raw_dir.join("gtp.pdf")
        pdf_path.write("%PDF-1.4\n")
        extracted_text = <<~TEXT
          Article - Tax - Property
          §6.5–101.
          (a) Decimal title body.
          §9.11–101.
          (a) Two-digit decimal body.
          §18.5–102.1.
          (a) Decimal title with decimal section body.
          §9–1602
          (a) Standalone period-less section header body.
        TEXT
        extractor = instance_double(MupdfExtractor, call: extracted_text)
        allow(MupdfExtractor).to receive(:new).with(pdf_path.to_s).and_return(extractor)

        stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)
        expect(stats["sections_upserted"]).to eq(4)

        expect(LawSection.find_by!(sway_locale: maryland, key: "art_gtp__sec_6.5-101").section).to eq("6.5-101")
        expect(LawSection.find_by!(sway_locale: maryland, key: "art_gtp__sec_9.11-101").section).to eq("9.11-101")
        expect(LawSection.find_by!(sway_locale: maryland, key: "art_gtp__sec_18.5-102.1").section).to eq("18.5-102.1")
        expect(LawSection.find_by!(sway_locale: maryland, key: "art_gtp__sec_9-1602").section).to eq("9-1602")
      end

      it "strips centered page numbers and structural dividers with periods while preserving statutory sentences and multi-page repeated sentences" do
        pdf_path = raw_dir.join("gen.pdf")
        pdf_path.write("%PDF-1.4\n")
        extracted_text = "Article - Environment\n" \
          "- 1 -\n" \
          "Title 1. Definitions.\n" \
          "Subtitle 5. Other Exemptions.\n" \
          "Part I. General Provisions.\n" \
          "§9–673.\n" \
          "Part VII of this subtitle applies only to Dorchester County.\n" \
          "- 274 -\n" \
          "\f" \
          "- 2 -\n" \
          "§9–674.\n" \
          "Subtitle 2 of this title applies in Allegany County.\n" \
          "Subject to the evaluation and reestablishment provisions of the Maryland Program Evaluation Act.\n" \
          "\f" \
          "- 3 -\n" \
          "Subject to the evaluation and reestablishment provisions of the Maryland Program Evaluation Act.\n" \
          "§9–675.\n" \
          "(a) Preserved subsection.\n"
        extractor = instance_double(MupdfExtractor, call: extracted_text)
        allow(MupdfExtractor).to receive(:new).with(pdf_path.to_s).and_return(extractor)

        stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)
        expect(stats["sections_upserted"]).to eq(3)

        sec1 = LawSection.find_by!(sway_locale: maryland, key: "art_gen__sec_9-673")
        expect(sec1.body).to eq("Part VII of this subtitle applies only to Dorchester County.")
        expect(sec1.body).not_to include("Title 1.")
        expect(sec1.body).not_to include("- 274 -")

        sec2 = LawSection.find_by!(sway_locale: maryland, key: "art_gen__sec_9-674")
        expect(sec2.body).to include("Subtitle 2 of this title applies in Allegany County.")
        expect(sec2.body).to include("Subject to the evaluation and reestablishment provisions")

        sec3 = LawSection.find_by!(sway_locale: maryland, key: "art_gen__sec_9-675")
        expect(sec3.body).to eq("(a) Preserved subsection.")
      end

      it "preserves first body line in section body using Page 1 article header as default title and handles bare repealed stubs" do
        pdf_path = raw_dir.join("gtp.pdf")
        pdf_path.write("%PDF-1.4\n")
        extracted_text = <<~TEXT
          - 1 -
          Article - Tax - Property
          §7–521.
          (a)
          (1) In this section words have meanings.
          §21–1308.
          §21–1309.
          (a) Active body for 21-1309.
        TEXT
        extractor = instance_double(MupdfExtractor, call: extracted_text)
        allow(MupdfExtractor).to receive(:new).with(pdf_path.to_s).and_return(extractor)

        stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)
        expect(stats["sections_upserted"]).to eq(3)

        sec1 = LawSection.find_by!(sway_locale: maryland, key: "art_gtp__sec_7-521")
        expect(sec1.title).to eq("Article - Tax - Property § 7-521")
        expect(sec1.body).to start_with("(a)")
        expect(sec1.body).to include("(1) In this section words have meanings.")

        stub = LawSection.find_by!(sway_locale: maryland, key: "art_gtp__sec_21-1308")
        expect(stub.title).to eq("Article - Tax - Property § 21-1308")
        expect(stub.body).to eq("Repealed or reserved")

        sec3 = LawSection.find_by!(sway_locale: maryland, key: "art_gtp__sec_21-1309")
        expect(sec3.title).to eq("Article - Tax - Property § 21-1309")
        expect(sec3.body).to eq("(a) Active body for 21-1309.")
      end

      it "merges duplicate section keys into a single LawSection and .md file with joined bodies and deduplicated title" do
        pdf_path = raw_dir.join("gag.pdf")
        pdf_path.write("%PDF-1.4\n")
        extracted_text = <<~TEXT
          Article - Agriculture
          §2–508. IN EFFECT
          Currently effective statutory body.
          §2–508. // EFFECTIVE SEPTEMBER 30, 2029 //
          Future effective statutory body.
        TEXT
        extractor = instance_double(MupdfExtractor, call: extracted_text)
        allow(MupdfExtractor).to receive(:new).with(pdf_path.to_s).and_return(extractor)

        stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)
        expect(stats["sections_upserted"]).to eq(1)
        expect(stats["files_written"]).to eq(1)

        sec = LawSection.find_by!(sway_locale: maryland, key: "art_gag__sec_2-508")
        expect(sec.title).to eq("Article - Agriculture § 2-508")
        expected_body = "IN EFFECT\n\nCurrently effective statutory body.\n\n---\n\n// EFFECTIVE SEPTEMBER 30, 2029 //\n\nFuture effective statutory body."
        expect(sec.body).to eq(expected_body)

        md_content = law_root.join("code/gag/2-508.md").read
        expect(md_content).to eq(expected_body)
      end
    end
  end

  describe "#load_corpus with unavailable engine" do
    it "raises StageError immediately" do
      adapter = described_class.new({engine: "unavailable"})
      expect {
        adapter.load_corpus(run: nil, sway_locale: maryland, law_root: @tmp_root)
      }.to raise_error(StageError, /law acquisition is unavailable/)
    end
  end

  describe "legacy law_source decoupling" do
    it "initializes without calling law_source" do
      strict_rules = instance_double(SwayLocale::JurisdictionRules, law_rules: {engine: :generic_xml})
      strict_locale = instance_double(SwayLocale, name: "strict_locale", jurisdiction_rules: strict_rules)

      adapter = described_class.new(strict_locale)
      expect(adapter.engine).to eq(:generic_xml)
    end

    it "does not fall back to law_source when law_rules is empty" do
      rules = double("Rules", law_rules: {}, law_source: :legacy_source)
      locale = instance_double(SwayLocale, jurisdiction_rules: rules)
      adapter = described_class.new(locale)
      expect(adapter.engine).to eq(:generic_rest)
    end

    it "does not check law_source on sway_locale during load_corpus" do
      adapter = described_class.new({engine: "unavailable"})
      no_source_locale = instance_double(SwayLocale, name: "no_source_locale", jurisdiction_rules: double("Rules"))
      expect {
        adapter.load_corpus(run: nil, sway_locale: no_source_locale, law_root: @tmp_root)
      }.to raise_error(StageError, /law acquisition is unavailable for no_source_locale/)
    end
  end

  describe "decoupled retrieval and parsing rules (TASK-ok5ox.50)" do
    it "initializes with explicit retrieval and parsing properties" do
      adapter = described_class.new({retrieval: "generic_xml", parsing: "uslm"})
      expect(adapter.retrieval).to eq(:generic_xml)
      expect(adapter.parsing).to eq(:uslm)
      expect(adapter.engine).to eq(:generic_xml)
    end

    it "supports alias keys retrieval_strategy and parser_format" do
      adapter = described_class.new({retrieval_strategy: "local_raw", parser_format: "generic_xml"})
      expect(adapter.retrieval).to eq(:local_raw)
      expect(adapter.parsing).to eq(:generic_xml)
    end

    it "falls back retrieval and parsing to engine when explicit properties are absent" do
      adapter = described_class.new({engine: "akoma_ntoso"})
      expect(adapter.retrieval).to eq(:akoma_ntoso)
      expect(adapter.parsing).to eq(:akoma_ntoso)
      expect(adapter.engine).to eq(:akoma_ntoso)
    end

    it "prioritizes explicit retrieval over engine" do
      adapter = described_class.new({engine: "generic_rest", retrieval: "generic_xml", parsing: "uslm"})
      expect(adapter.retrieval).to eq(:generic_xml)
      expect(adapter.parsing).to eq(:uslm)
      expect(adapter.engine).to eq(:generic_rest)
    end

    it "extracts decoupled retrieval and parsing from JurisdictionRules object" do
      rules = instance_double(
        SwayLocale::JurisdictionRules,
        law_rules: {retrieval: "git_repo", parsing: "akoma_ntoso"},
        law_retrieval: "git_repo",
        law_parsing: "akoma_ntoso"
      )
      adapter = described_class.new(rules)
      expect(adapter.retrieval).to eq(:git_repo)
      expect(adapter.parsing).to eq(:akoma_ntoso)
    end

    it "extracts decoupled retrieval and parsing via retrieval_for and parsing_for duck-typing" do
      duck = double("RulesProxy", law_rules: {engine: "local_raw"})
      allow(duck).to receive(:retrieval_for).with(:law).and_return("generic_html")
      allow(duck).to receive(:parsing_for).with(:law).and_return("generic_xml")

      adapter = described_class.new(duck)
      expect(adapter.retrieval).to eq(:generic_html)
      expect(adapter.parsing).to eq(:generic_xml)
      expect(adapter.engine).to eq(:local_raw)
    end

    it "short-circuits #load_corpus when retrieval is unavailable" do
      adapter = described_class.new({retrieval: "unavailable", parsing: "uslm"})
      expect {
        adapter.load_corpus(run: nil, sway_locale: maryland, law_root: @tmp_root)
      }.to raise_error(StageError, /law acquisition is unavailable for #{maryland.name}/)
    end

    it "routes corpus acquisition based on retrieval property" do
      adapter = described_class.new({retrieval: "akoma_ntoso", parsing: "uslm"})
      expect {
        adapter.load_corpus(run: nil, sway_locale: maryland, law_root: @tmp_root, service: nil)
      }.to raise_error(ArgumentError, /FetchLawService required for Akoma Ntoso law loading/)
    end
  end

  describe "configured local_path in raw corpus fallback" do
    it "parses statute PDFs via load_raw_corpus when retrieval is local and local_path is configured" do
      law_root = Legislation::Paths.law(sway_locale: maryland)
      raw_dir = law_root.join("raw")
      raw_dir.mkpath
      pdf_path = raw_dir.join("gag.pdf")
      pdf_path.write("%PDF-1.4\n")

      extracted_text = <<~TEXT
        § 1–101. Definitions.
        In this article, words have meanings.
      TEXT
      extractor = instance_double(MupdfExtractor, call: extracted_text)
      expect(MupdfExtractor).to receive(:new).with(pdf_path.to_s).and_return(extractor)

      adapter = described_class.new({retrieval: "local", parsing: "pdf_statute_sections", local_path: "raw"})
      stats = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: law_root)
      expect(stats).to include("sections_upserted" => 1, "articles_processed" => 1)
    end

    it "rejects local_path with directory traversal" do
      adapter = described_class.new({retrieval: "local", parsing: "generic_xml", local_path: "../outside"})
      expect {
        adapter.load_corpus(run: nil, sway_locale: maryland, law_root: @tmp_root)
      }.to raise_error(StageError, /local_path must stay inside the law root/)
    end

    it "raises StageError with diagnostic path when no corpus files exist in configured local_path or fallback dirs" do
      adapter = described_class.new({retrieval: "local_raw", parsing: "generic_xml", local_path: "raw"})
      expect {
        adapter.load_corpus(run: nil, sway_locale: maryland, law_root: @tmp_root)
      }.to raise_error(StageError, /fetch_law: missing #{maryland.name} law corpus under #{@tmp_root}/)
    end
  end

  describe "#load_corpus dispatch and #record_section security" do
    it "dispatches :akoma_ntoso to #load_akoma_ntoso_corpus" do
      adapter = described_class.new({engine: "akoma_ntoso"})
      allow(adapter).to receive(:load_akoma_ntoso_corpus).and_return({"sections_upserted" => 5})

      result = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: @tmp_root)
      expect(result).to eq({"sections_upserted" => 5})
      expect(adapter).to have_received(:load_akoma_ntoso_corpus)
    end

    it "dispatches :uslm_xml to #load_raw_corpus when CongressLawCorpusService is not active" do
      hide_const("Legislation::CongressLawCorpusService")
      adapter = described_class.new({engine: "uslm_xml"})
      allow(adapter).to receive(:load_raw_corpus).and_return({"sections_upserted" => 15})

      result = adapter.load_corpus(run: nil, sway_locale: maryland, law_root: @tmp_root)
      expect(result).to eq({"sections_upserted" => 15})
      expect(adapter).to have_received(:load_raw_corpus)
    end

    it "rejects path traversal and null bytes in article or section identifiers under uslm_xml parsing" do
      adapter = described_class.new({retrieval: "git_repo", parsing: "uslm_xml"})
      stats = {"sections_upserted" => 0, "files_written" => 0}
      section_index = {}

      [
        ["../unsafe", "101"],
        ["5", "101/../../../etc"],
        ["5", "101\\..\\etc"],
        ["5", "101\x00extra"]
      ].each do |article_id, section_id|
        expect {
          adapter.send(:record_section, article_id, section_id, "Title", "Body", @tmp_root, maryland, stats, section_index)
        }.to raise_error(StageError, "fetch_law: unsafe US Code section identifier")
      end
    end

    it "merges multi-part USLM sections into variant titles and concatenated body without double-counting" do
      allow(FetchLawService::LawSectionUpsert).to receive(:call).and_return(true)
      adapter = described_class.new({retrieval: "git_repo", parsing: "uslm_xml"})
      stats = {"sections_upserted" => 0, "files_written" => 0}
      section_index = {}

      adapter.send(:record_section, "5", "552", "Freedom of Information", "First Body Content", @tmp_root, maryland, stats, section_index)
      adapter.send(:record_section, "5", "552", "Public Records Addendum", "Second Body Content", @tmp_root, maryland, stats, section_index)

      expect(stats["sections_upserted"]).to eq(1)
      expect(stats["files_written"]).to eq(1)
      expect(section_index["art_5__sec_552"]["title"]).to eq("Freedom of Information; Public Records Addendum")
      file_content = File.read(@tmp_root.join(section_index["art_5__sec_552"]["path"]))
      expect(file_content).to include("## Freedom of Information", "First Body Content", "## Public Records Addendum", "Second Body Content")
    end
  end
end
