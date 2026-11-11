# frozen_string_literal: true

require "rails_helper"
require "zip"

# @lat: [[rbs-signatures#Why a spec's helpers are invisible to Steep]]
module CongressCorpusRegressionSpecHelpers
  def self.zip_bytes(entries)
    buffer = Zip::OutputStream.write_buffer do |zip|
      entries.each do |name, body|
        zip.put_next_entry(name)
        zip.write(body)
      end
    end
    buffer.rewind
    buffer.read.to_s
  end

  def self.stream(body, status: 200)
    proc do |_url, &configure|
      request = Faraday.new.send(:build_request, :get)
      configure&.call(request)
      env = Faraday::Env.from({status: status})
      request.options.on_data&.call(body, body.bytesize, env)
      Faraday::Response.new(Faraday::Env.from({status: status, response_headers: Faraday::Utils::Headers.new, body: ""}))
    end
  end
end

RSpec.describe "Congress corpus acquisition regressions" do
  # @type self: CongressCorpusRegressionSpecContext
  let(:congress_locale) { create(:sway_locale, :congress) }
  let(:law_root) { Legislation::Paths.law(sway_locale: congress_locale) }
  let(:http) { instance_double(Faraday::Connection) }
  let(:catalog_url) { Legislation::CongressLawCorpusService::CATALOG_URL }
  let(:archive_path) { "releasepoints/us/pl/119/103/xml_usc42@119-103.zip" }
  let(:archive_url) { "https://uscode.house.gov/download/#{archive_path}" }
  let(:catalog) { %(<a href="#{archive_path}">Title 42 XML</a>) }
  let(:xml) do
    <<~XML
      <uscDoc xmlns="http://xml.house.gov/schemas/uslm/1.0" identifier="/us/usc/t42">
        <main><title identifier="/us/usc/t42"><num value="42">Title 42—</num><heading>PUBLIC HEALTH</heading>
          <chapter><section identifier="/us/usc/t42/s1983"><num value="1983">§ 1983.</num>
            <heading>Civil action for deprivation of rights</heading>
            <subsection><num>(a)</num><content><p>Every person who, under color of any statute, subjects another to deprivation.</p></content></subsection>
            <subsection><num>(b)</num><content><p>Every citizen retains the remedies provided.</p></content></subsection>
            <notes><note><section identifier="/us/usc/t42/s999"><num value="999">999</num><heading>Historical section</heading><content>Historical text.</content></section></note></notes>
          </section>
          <section identifier="/us/usc/t42/s1984" status="repealed"><num value="1984">§ 1984.</num><heading>Repealed</heading><content>Repealed by Public Law.</content></section></chapter>
        </title></main>
      </uscDoc>
    XML
  end
  let(:archive) { CongressCorpusRegressionSpecHelpers.zip_bytes({"usc42.xml" => xml}) }
  let(:run) { instance_double(LegislationPipelineRun, effective_sway_locale: congress_locale) }

  around do |example|
    Dir.mktmpdir("congress_corpus_regression") do |directory|
      @tmp_root = Pathname.new(directory)
      example.run
    end
  end

  before do
    allow(Legislation::Paths).to receive(:root).and_return(@tmp_root)
    allow(Sway::FaradayStack).to receive(:build).and_return(http)
    allow(http).to receive(:get).with(catalog_url, &CongressCorpusRegressionSpecHelpers.stream(catalog))
    allow(http).to receive(:get).with(archive_url, &CongressCorpusRegressionSpecHelpers.stream(archive))
  end

  # @lat: [[legislation-pipeline#Congress law corpus acquisition]]
  it "bootstraps a fresh FetchLawService run from official namespaced USLM ZIPs" do
    expect(law_root.join("raw")).not_to exist

    stats = FetchLawService.new(run: run).call

    expect(stats).to include("sections_upserted" => 2, "articles_processed" => 1)
    expect(LawSection.where(sway_locale: congress_locale).pluck(:key)).to match_array(%w[art_42__sec_1983 art_42__sec_1984])
    section = LawSection.find_by!(sway_locale: congress_locale, key: "art_42__sec_1983")
    expect(section.title).to eq("Civil action for deprivation of rights")
    expect(section.body).to include("Every person who, under color")
    expect(section.body).to include("Every citizen retains the remedies provided.")
    expect(section.body).not_to include("Historical section", "Historical text.")
    expect(law_root.join("raw/usc42.xml").read).to eq(xml)
    expect(law_root.join(section.source_path).read).to eq(section.body)
    index = JSON.parse(law_root.join("section_index.json").read)
    expect(index.fetch("art_42__sec_1984").fetch("status")).to eq("repealed")
    expect(index.keys).not_to include("art_42__sec_999")
  end

  it "reuses the published corpus without another HTTP request or duplicate sections" do
    FetchLawService.new(run: run).call
    expect(http).not_to receive(:get)

    expect { FetchLawService.new(run: run).call }.not_to change { LawSection.where(sway_locale: congress_locale).count }
  end

  it "does not publish the first title when the next download fails and retries cleanly" do
    second_path = "releasepoints/us/pl/119/103/xml_usc43@119-103.zip"
    second_url = "https://uscode.house.gov/download/#{second_path}"
    two_titles = catalog + %(<a href="#{second_path}">Title 43 XML</a>)
    allow(http).to receive(:get).with(catalog_url, &CongressCorpusRegressionSpecHelpers.stream(two_titles))
    allow(http).to receive(:get).with(second_url, &CongressCorpusRegressionSpecHelpers.stream("unavailable", status: 503))

    expect { FetchLawService.new(run: run).call }.to raise_error(StageError, /HTTP 503/)
    expect(law_root.join("raw")).not_to exist
    expect(law_root.join("section_index.json")).not_to exist
    expect(LawSection.where(sway_locale: congress_locale)).to be_empty

    allow(http).to receive(:get).with(catalog_url, &CongressCorpusRegressionSpecHelpers.stream(catalog))
    expect { FetchLawService.new(run: run).call }.to change { LawSection.where(sway_locale: congress_locale).count }.by(2)
  end

  it "rolls back imported rows and leaves no raw cache when the XML fails after a section" do
    malformed = xml.sub("</title></main>", "</broken></main>")
    bad_archive = CongressCorpusRegressionSpecHelpers.zip_bytes({"usc42.xml" => malformed})
    allow(http).to receive(:get).with(archive_url, &CongressCorpusRegressionSpecHelpers.stream(bad_archive))

    expect { FetchLawService.new(run: run).call }.to raise_error(StageError)
    expect(LawSection.where(sway_locale: congress_locale)).to be_empty
    expect(law_root.join("raw")).not_to exist
    expect(law_root.join("section_index.json")).not_to exist
  end

  it "rejects a syntactically valid downloaded document with no statutory sections" do
    empty_archive = CongressCorpusRegressionSpecHelpers.zip_bytes({"usc42.xml" => "<unrelated/>"})
    allow(http).to receive(:get).with(archive_url, &CongressCorpusRegressionSpecHelpers.stream(empty_archive))

    expect { FetchLawService.new(run: run).call }.to raise_error(StageError)
    expect(law_root.join("raw")).not_to exist
    expect(law_root.join("section_index.json")).not_to exist
  end

  it "rejects a corrupt ZIP before it becomes a reusable cache" do
    allow(http).to receive(:get).with(archive_url, &CongressCorpusRegressionSpecHelpers.stream("not a zip"))

    expect { FetchLawService.new(run: run).call }.to raise_error(StageError)
    expect(law_root.join("raw")).not_to exist
  end

  it "rejects valid XML whose archive checksum does not match its declared contents" do
    corrupted = archive.dup
    central_directory = corrupted.index("PK\x01\x02")
    raise "missing test archive directory" unless central_directory

    corrupted[central_directory.to_i + 16, 4] = [0].pack("V")
    allow(http).to receive(:get).with(archive_url, &CongressCorpusRegressionSpecHelpers.stream(corrupted))

    expect { FetchLawService.new(run: run).call }.to raise_error(StageError, /incomplete US Code title/)
    expect(law_root.join("raw")).not_to exist
    expect(LawSection.where(sway_locale: congress_locale)).to be_empty
  end

  it "rejects archive paths escaping the title directory" do
    malicious = CongressCorpusRegressionSpecHelpers.zip_bytes({"../escaped.xml" => xml})
    allow(http).to receive(:get).with(archive_url, &CongressCorpusRegressionSpecHelpers.stream(malicious))

    expect { FetchLawService.new(run: run).call }.to raise_error(StageError, /ZIP contents/)
    expect(law_root.join("escaped.xml")).not_to exist
    expect(law_root.join("raw")).not_to exist
  end

  it "rejects untrusted archive hosts advertised in the official catalog" do
    foreign = %(<a href="https://example.com/download/releasepoints/xml_usc42@119-103.zip">XML</a>)
    allow(http).to receive(:get).with(catalog_url, &CongressCorpusRegressionSpecHelpers.stream(foreign))

    expect { FetchLawService.new(run: run).call }.to raise_error(StageError, /archive URL/)
    expect(http).not_to have_received(:get).with(archive_url)
  end

  it "enforces the compressed byte cap on streamed responses without Content-Length" do
    stub_const("Legislation::CongressLawCorpusService::MAX_ARCHIVE_BYTES", archive.bytesize - 1)

    expect { FetchLawService.new(run: run).call }.to raise_error(StageError, /exceeds/)
    expect(law_root.join("raw")).not_to exist
  end

  it "enforces the expanded title byte cap" do
    stub_const("Legislation::CongressLawCorpusService::MAX_TITLE_BYTES", xml.bytesize - 1)

    expect { FetchLawService.new(run: run).call }.to raise_error(StageError, /byte cap/)
    expect(law_root.join("raw")).not_to exist
  end

  it "enforces the aggregate expanded byte cap" do
    stub_const("Legislation::CongressLawCorpusService::MAX_CORPUS_BYTES", xml.bytesize - 1)

    expect { FetchLawService.new(run: run).call }.to raise_error(StageError, /byte cap/)
    expect(law_root.join("raw")).not_to exist
  end

  it "discards a partial response when a retry starts with a larger first chunk" do
    allow(http).to receive(:get).with(archive_url) do |_url, &configure|
      request = Faraday.new.send(:build_request, :get)
      configure.call(request)
      env = Faraday::Env.from({status: 200})
      callback = request.options.on_data
      callback.call("bad", 3, env)
      callback.call(archive, archive.bytesize, env)
      Faraday::Response.new(Faraday::Env.from({status: 200, response_headers: Faraday::Utils::Headers.new, body: ""}))
    end

    expect { FetchLawService.new(run: run).call }.not_to raise_error
    expect(law_root.join("raw/usc42.xml").read).to eq(xml)
  end

  it "excludes historical appendix ZIPs whose section identifiers belong to separate numbering schemes" do
    appendix = "releasepoints/us/pl/119/103/xml_usc05a@119-103.zip"
    mixed_catalog = catalog + %(<a href="#{appendix}">Title 5 Appendix XML</a>)
    allow(http).to receive(:get).with(catalog_url, &CongressCorpusRegressionSpecHelpers.stream(mixed_catalog))
    expect(http).not_to receive(:get).with("https://uscode.house.gov/download/#{appendix}")

    expect(FetchLawService.new(run: run).call).to include("sections_upserted" => 2)
  end

  it "skips an explicitly reserved title whose published XML link has no statutory archive" do
    reserved_path = "releasepoints/us/pl/119/103/xml_usc53@119-103.zip"
    official_catalog = <<~HTML
      <div class="uscitem">
        <div class="usctitle">Title 42 - The Public Health and Welfare</div>
        <div class="itemdownloadlinks"><a href="#{archive_path}">[XML]</a></div>
      </div>
      <div class="uscitem">
        <div class="usctitle">Title 53 [Reserved]</div>
        <div class="itemdownloadlinks"><a href="#{reserved_path}">[XML]</a></div>
      </div>
    HTML
    allow(http).to receive(:get).with(catalog_url, &CongressCorpusRegressionSpecHelpers.stream(official_catalog))
    expect(http).not_to receive(:get).with("https://uscode.house.gov/download/#{reserved_path}")

    expect(FetchLawService.new(run: run).call).to include("sections_upserted" => 2, "articles_processed" => 1)
    expect(law_root.join("raw/usc42.xml")).to exist
    expect(law_root.join("raw/usc53.xml")).not_to exist
  end

  it "preserves distinct enacted versions sharing a citation without accumulating copies on rerun" do
    duplicate_xml = <<~XML
      <uscDoc xmlns="http://xml.house.gov/schemas/uslm/1.0" identifier="/us/usc/t5">
        <main><title identifier="/us/usc/t5"><num value="5">Title 5—</num><heading>GOVERNMENT ORGANIZATION</heading>
          <chapter>
            <section identifier="/us/usc/t5/s3598" status="repealed"><num value="3598">§ 3598.</num>
              <heading>Former reserve service authority</heading>
              <content><p>The former enacted version authorized reserve appointments.</p></content>
            </section>
            <section identifier="/us/usc/t5/s3598"><num value="3598">§ 3598.</num>
              <heading>FBI Reserve Service</heading>
              <content><p>The separately enacted version authorizes a reserve service.</p></content>
            </section>
          </chapter>
        </title></main>
      </uscDoc>
    XML
    title_path = "releasepoints/us/pl/119/103/xml_usc05@119-103.zip"
    title_archive = CongressCorpusRegressionSpecHelpers.zip_bytes({"usc05.xml" => duplicate_xml})
    allow(http).to receive(:get).with(catalog_url, &CongressCorpusRegressionSpecHelpers.stream(%(<a href="#{title_path}">[XML]</a>)))
    allow(http).to receive(:get).with("https://uscode.house.gov/download/#{title_path}", &CongressCorpusRegressionSpecHelpers.stream(title_archive))

    stats = FetchLawService.new(run: run).call

    expect(stats).to include("sections_upserted" => 1, "files_written" => 1, "articles_processed" => 1)
    expect(LawSection.where(sway_locale: congress_locale).pluck(:key)).to eq(["art_5__sec_3598"])
    section = LawSection.find_by!(sway_locale: congress_locale, key: "art_5__sec_3598")
    body = section.body
    expect(body).to include("Former reserve service authority", "FBI Reserve Service")
    expect(body.scan("The former enacted version authorized reserve appointments.").size).to eq(1)
    expect(body.scan("The separately enacted version authorizes a reserve service.").size).to eq(1)
    index = JSON.parse(law_root.join("section_index.json").read)
    expect(index.keys).to eq(["art_5__sec_3598"])
    expect(index.fetch("art_5__sec_3598").fetch("status")).to eq("active")
    expect(law_root.join(section.source_path).read).to eq(body)

    expect(http).not_to receive(:get)
    expect { FetchLawService.new(run: run).call }.not_to change { LawSection.where(sway_locale: congress_locale).count }
    expect(section.reload.body).to eq(body)
    expect(law_root.join(section.source_path).read).to eq(body)
  end
end
