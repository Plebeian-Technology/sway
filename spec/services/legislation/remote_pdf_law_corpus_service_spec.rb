# frozen_string_literal: true

require "rails_helper"

module RemotePdfLawCorpusSpecHelpers
  # @type self: RemotePdfLawCorpusServiceSpecContext
  def service(locale: maryland)
    Legislation::RemotePdfLawCorpusService.new(sway_locale: locale, law_root: law_root, http: http)
  end

  def stub_catalog(codes: ["gag", "c"])
    articles = codes.map { |code| {"DisplayText" => code.upcase, "Value" => code} }
    stub_request(:get, catalog_url)
      .with(query: {"enactments" => "true"})
      .to_return(status: 200, body: JSON.generate(articles))
  end

  def stub_link(article_code, pdf_url:, status: 200)
    stub_request(:get, link_url)
      .with(query: {"articleCode" => article_code, "enactments" => "true"})
      .to_return(status: status, body: JSON.generate(pdf_url))
  end

  def stub_link_sequence(article_code, *pdf_urls)
    remove_request_stub(@article_link_stub)
    @article_link_stub = stub_request(:get, link_url)
      .with(query: {"articleCode" => article_code, "enactments" => "true"})
      .to_return(*pdf_urls.map { |url| {status: 200, body: JSON.generate(url)} })
  end

  def stub_pdf(url, body, status: 200)
    stub_request(:get, url).to_return(status: status, body: body)
  end
end

RSpec.describe Legislation::RemotePdfLawCorpusService do
  # @type self: RemotePdfLawCorpusServiceSpecContext
  include RemotePdfLawCorpusSpecHelpers

  let(:maryland) { create(:sway_locale, :maryland) }
  let(:http) { Faraday.new(url: base_url) }
  let(:law_root) { @tmp_root.join("legislation", maryland.name, "law") }
  let(:raw_root) { law_root.join("raw") }
  let(:base_url) { "https://mgaleg.maryland.gov" }
  let(:catalog_url) { "#{base_url}/mgawebsite/api/Laws/GetArticles" }
  let(:link_url) { "#{base_url}/mgawebsite/api/Laws/GetArticleLink" }
  let(:pdf_url) { "#{base_url}/2027RS/Statute_Web/gag/gag.pdf" }
  let(:pdf_bytes) { "%PDF-1.7\nsynthetic statute bytes" }

  around do |example|
    Dir.mktmpdir("remote_pdf_law_corpus") do |directory|
      @tmp_root = Pathname.new(directory)
      example.run
    end
  end

  before do
    allow(Legislation::Paths).to receive(:root).and_return(@tmp_root)
    @catalog_stub = stub_catalog
    @article_link_stub = stub_link("gag", pdf_url: pdf_url)
    stub_pdf(pdf_url, pdf_bytes)
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Maryland PDF law corpus acquisition#Filters and resolves official article URLs before caching PDFs]]
  it "downloads only statutory article PDFs from the resolved official URLs and records their digests" do
    expect(service.call).to eq(:downloaded)

    expect(raw_root.join("gag.pdf").binread).to eq(pdf_bytes)
    expect(raw_root.join("c.pdf")).not_to exist
    manifest = JSON.parse(raw_root.join("manifest.json").read)
    expect(manifest).to eq({
      "version" => 1,
      "articles" => {
        "gag" => {
          "url" => pdf_url,
          "file" => "gag.pdf",
          "sha256" => Digest::SHA256.hexdigest(pdf_bytes)
        }
      }
    })
    expect(WebMock).not_to have_requested(:get, link_url).with(query: hash_including("articleCode" => "c"))
  end

  it "rejects a malformed article catalog without publishing a partial corpus" do
    remove_request_stub(@catalog_stub)
    stub_request(:get, catalog_url)
      .with(query: {"enactments" => "true"})
      .to_return(status: 200, body: JSON.generate("articles" => [{"Value" => "gag"}]))

    expect { service.call }.to raise_error(StageError, /article catalog must be an array/)

    expect(raw_root).not_to exist
    expect(WebMock).not_to have_requested(:get, link_url)
    expect(WebMock).not_to have_requested(:get, pdf_url)
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Maryland PDF law corpus acquisition#Skips PDF downloads for an unchanged verified corpus]]
  it "returns unchanged without downloading PDFs when the resolved manifest and verified cache match" do
    expect(service.call).to eq(:downloaded)

    expect(service.call).to eq(:unchanged)

    expect(WebMock).to have_requested(:get, catalog_url).with(query: {"enactments" => "true"}).twice
    expect(WebMock).to have_requested(:get, link_url).with(query: {"articleCode" => "gag", "enactments" => "true"}).twice
    expect(WebMock).to have_requested(:get, pdf_url).once
  end

  it "refreshes when a session-versioned PDF URL changes without an article catalog change" do
    next_pdf_url = "#{base_url}/2028RS/Statute_Web/gag/gag.pdf"
    next_pdf_bytes = "%PDF-1.7\nnext session statute bytes"
    stub_link_sequence("gag", pdf_url, next_pdf_url)
    stub_pdf(next_pdf_url, next_pdf_bytes)

    expect(service.call).to eq(:downloaded)
    expect(service.call).to eq(:downloaded)

    expect(raw_root.join("gag.pdf").binread).to eq(next_pdf_bytes)
    manifest = JSON.parse(raw_root.join("manifest.json").read)
    expect(manifest.dig("articles", "gag", "url")).to eq(next_pdf_url)
  end

  it "reacquires a missing PDF even when the URL manifest is unchanged" do
    expect(service.call).to eq(:downloaded)
    raw_root.join("gag.pdf").delete

    expect(service.call).to eq(:downloaded)

    expect(raw_root.join("gag.pdf").binread).to eq(pdf_bytes)
    expect(WebMock).to have_requested(:get, pdf_url).twice
  end

  it "reacquires a PDF whose digest no longer matches the unchanged manifest" do
    expect(service.call).to eq(:downloaded)
    raw_root.join("gag.pdf").binwrite("%PDF-1.7\nchanged bytes")

    expect(service.call).to eq(:downloaded)

    expect(raw_root.join("gag.pdf").binread).to eq(pdf_bytes)
    expect(WebMock).to have_requested(:get, pdf_url).twice
  end

  it "rejects unsafe download hosts without publishing a corpus" do
    unsafe_url = "https://example.com/gag.pdf"
    remove_request_stub(@article_link_stub)
    stub_link("gag", pdf_url: unsafe_url)

    expect { service.call }.to raise_error(StageError, /unexpected.*PDF URL|unsafe.*PDF URL/i)
    expect(raw_root).not_to exist
    expect(WebMock).not_to have_requested(:get, unsafe_url)
  end

  it "rejects a non-PDF response before publishing a corpus" do
    stub_pdf(pdf_url, "not a PDF")

    expect { service.call }.to raise_error(StageError, /PDF signature/)
    expect(raw_root).not_to exist
  end

  it "rejects a partial response before publishing a corpus" do
    stub_pdf(pdf_url, pdf_bytes, status: 206)

    expect { service.call }.to raise_error(StageError, /HTTP 206/)
    expect(raw_root).not_to exist
  end

  it "preserves the verified cache and reports cached_offline after a refresh download fails" do
    expect(service.call).to eq(:downloaded)
    prior_manifest = raw_root.join("manifest.json").read
    next_pdf_url = "#{base_url}/2028RS/Statute_Web/gag/gag.pdf"
    remove_request_stub(@article_link_stub)
    @article_link_stub = stub_link("gag", pdf_url: next_pdf_url)
    stub_pdf(next_pdf_url, "upstream unavailable", status: 503)

    expect(service.call).to eq(:cached_offline)

    expect(raw_root.join("gag.pdf").binread).to eq(pdf_bytes)
    expect(raw_root.join("manifest.json").read).to eq(prior_manifest)
  end

  it "raises a stage error when acquisition fails and no complete cache exists" do
    stub_pdf(pdf_url, "unavailable", status: 503)

    expect { service.call }.to raise_error(StageError, /HTTP 503.*no complete.*cache/i)
    expect(raw_root).not_to exist
  end

  it "keeps the prior corpus when a later article download fails after catalog discovery" do
    expect(service.call).to eq(:downloaded)
    prior_manifest = raw_root.join("manifest.json").read
    remove_request_stub(@catalog_stub)
    @catalog_stub = stub_catalog(codes: ["gag", "gbg", "c"])
    next_pdf_url = "#{base_url}/2027RS/Statute_Web/gbg/gbg.pdf"
    stub_link("gbg", pdf_url: next_pdf_url)
    stub_pdf(next_pdf_url, "unavailable", status: 503)

    expect(service.call).to eq(:cached_offline)

    expect(raw_root.join("gag.pdf").binread).to eq(pdf_bytes)
    expect(raw_root.join("gbg.pdf")).not_to exist
    expect(raw_root.join("manifest.json").read).to eq(prior_manifest)
  end

  it "restores the verified corpus when publication of its replacement fails" do
    expect(service.call).to eq(:downloaded)
    prior_manifest = raw_root.join("manifest.json").read
    next_pdf_url = "#{base_url}/2028RS/Statute_Web/gag/gag.pdf"
    next_pdf_bytes = "%PDF-1.7\nreplacement statute bytes"
    remove_request_stub(@article_link_stub)
    @article_link_stub = stub_link("gag", pdf_url: next_pdf_url)
    stub_pdf(next_pdf_url, next_pdf_bytes)
    original_rename = File.method(:rename)
    failed_publish = false
    allow(File).to receive(:rename) do |source, target|
      if !failed_publish && Pathname(target) == raw_root && Pathname(source) != raw_root
        failed_publish = true
        raise Errno::EIO
      end
      original_rename.call(source, target)
    end

    expect(service.call).to eq(:cached_offline)

    expect(raw_root.join("gag.pdf").binread).to eq(pdf_bytes)
    expect(raw_root.join("manifest.json").read).to eq(prior_manifest)
  end

  it "rejects local paths that are absolute or escape the locale law root" do
    ["/tmp/law/raw", "../raw"].each do |local_path|
      law_rules = (maryland.jurisdiction_rules.law_rules || {}).merge(local_path: local_path)
      rules = instance_double(SwayLocale::JurisdictionRules, law_rules: law_rules)
      locale = instance_double(SwayLocale, name: "test-locale", jurisdiction_rules: rules)
      configured = described_class.new(sway_locale: locale, law_root: law_root, http: http)

      expect { configured.call }.to raise_error(StageError, /local_path.*inside.*law root/i)
    end
  end
end
