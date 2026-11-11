# frozen_string_literal: true

require "rails_helper"

# @lat: [[rbs-signatures#Why a spec's helpers are invisible to Steep]]
module FetchLawCorpusServiceSpecHelpers
  TMP_LAW_ROOT = LegislationTestArtifacts.root_for("fetch_law_corpus_service").freeze
  FIXTURE_TARBALL = Rails.root.join("spec", "fixtures", "legislation", "law_xml_main.tar.gz").to_s.freeze
  CHARTER_REL = "law-xml-main/us/md/cities/baltimore/charter.xml"

  def self.raw_root
    Pathname.new(TMP_LAW_ROOT).join("raw")
  end

  def self.tarball_bytes
    File.binread(FIXTURE_TARBALL)
  end

  def self.write_cached_charter(content = "<cached/>")
    dir = raw_root.join("law-xml-main/us/md/cities/baltimore")
    dir.mkpath
    dir.join("charter.xml").write(content)
  end

  def self.write_commit_sha(sha)
    raw_root.mkpath
    raw_root.join(".commit_sha").write(sha)
  end

  # The two shapes Faraday hands a streaming caller: the request to
  # configure, and the env passed beside each chunk. Named here so each call
  # doesn't define a fresh anonymous class.
  StubRequestOptions = Struct.new(:on_data)
  StubRequest = Struct.new(:options)
  StubChunkEnv = Struct.new(:status)

  # @lat: [[outbound-fetch-safety#An oversized download is stopped rather than refused afterwards]]
  def self.tarball_stream(bytes:, status: 200, headers: {}, chunk_size: 8192)
    proc do |_url, &configure|
      request = StubRequest.new(StubRequestOptions.new(nil))
      configure&.call(request)
      handler = request.options.on_data

      # Split on BYTES, not characters — the archive is binary and a character
      # boundary would move the cut. `running` is the total delivered so far,
      # the second thing Faraday hands a chunk handler.
      running = 0
      bytes.bytes.each_slice(chunk_size) do |slice|
        chunk = slice.pack("C*")
        running += chunk.bytesize
        handler&.call(chunk, running, StubChunkEnv.new(status))
      end

      # Braces, because `from` takes ONE positional value — Ruby would fold
      # bare keywords into that hash on its own, but writing it out lets the
      # type checker read the call correctly.
      Faraday::Response.new(
        Faraday::Env.from({status: status, response_headers: Faraday::Utils::Headers.new(headers), body: ""})
      )
    end
  end
end

RSpec.describe FetchLawCorpusService do
  around do |example|
    FileUtils.rm_rf(FetchLawCorpusServiceSpecHelpers::TMP_LAW_ROOT)
    with_app_config(:legislation, legislation_law_root: FetchLawCorpusServiceSpecHelpers::TMP_LAW_ROOT) {
      example.run
    }
  ensure
    FileUtils.rm_rf(FetchLawCorpusServiceSpecHelpers::TMP_LAW_ROOT)
  end

  describe "#call — fresh download" do
    it "downloads, extracts charter.xml under raw/, and records the commit SHA" do
      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).with(FetchLawCorpusService::COMMITS_URL)
        .and_return(instance_double(Faraday::Response, status: 200, body: {"sha" => "abc123"}.to_json))
      allow(http).to receive(:get).with(
        FetchLawCorpusService::TARBALL_URL,
        &FetchLawCorpusServiceSpecHelpers.tarball_stream(bytes: FetchLawCorpusServiceSpecHelpers.tarball_bytes)
      )

      expect(described_class.new(run: nil, http: http).call).to eq(:downloaded)

      charter = FetchLawCorpusServiceSpecHelpers.raw_root.join(FetchLawCorpusServiceSpecHelpers::CHARTER_REL)
      expect(charter.exist?).to be(true)
      expect(charter.read).to include("open.law/schemas/library")
      expect(FetchLawCorpusServiceSpecHelpers.raw_root.join(".commit_sha").read).to eq("abc123")
    end
  end

  describe "#call — idempotent skip" do
    it "does not download the tarball when the stored SHA matches and a corpus is present" do
      FetchLawCorpusServiceSpecHelpers.write_commit_sha("abc123")
      FetchLawCorpusServiceSpecHelpers.write_cached_charter

      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).with(FetchLawCorpusService::COMMITS_URL)
        .and_return(instance_double(Faraday::Response, status: 200, body: {"sha" => "abc123"}.to_json))

      expect(described_class.new(run: nil, http: http).call).to eq(:unchanged)
      expect(http).not_to have_received(:get).with(FetchLawCorpusService::TARBALL_URL)
    end
  end

  # #unchanged? is the fourth unguarded `exist?`-then-`read` in the pipeline.
  # 'Cannot read the marker' should equal 'no marker file': download again —
  # instead a filesystem error killed the run.
  describe "#call — unreadable SHA marker (A1-WR-02)" do
    it "re-downloads rather than raising when .commit_sha cannot be read" do
      FetchLawCorpusServiceSpecHelpers.raw_root.join(".commit_sha").mkpath
      FetchLawCorpusServiceSpecHelpers.write_cached_charter

      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).with(FetchLawCorpusService::COMMITS_URL)
        .and_return(instance_double(Faraday::Response, status: 200, body: {"sha" => "abc123"}.to_json))
      allow(http).to receive(:get).with(
        FetchLawCorpusService::TARBALL_URL,
        &FetchLawCorpusServiceSpecHelpers.tarball_stream(bytes: FetchLawCorpusServiceSpecHelpers.tarball_bytes)
      )

      expect { described_class.new(run: nil, http: http).call }.not_to raise_error
    end
  end

  describe "#call — re-download on SHA drift" do
    it "downloads again when the upstream SHA changed" do
      FetchLawCorpusServiceSpecHelpers.write_commit_sha("old-sha")
      FetchLawCorpusServiceSpecHelpers.write_cached_charter

      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).with(FetchLawCorpusService::COMMITS_URL)
        .and_return(instance_double(Faraday::Response, status: 200, body: {"sha" => "new-sha"}.to_json))
      allow(http).to receive(:get).with(
        FetchLawCorpusService::TARBALL_URL,
        &FetchLawCorpusServiceSpecHelpers.tarball_stream(bytes: FetchLawCorpusServiceSpecHelpers.tarball_bytes)
      )

      expect(described_class.new(run: nil, http: http).call).to eq(:downloaded)
      expect(FetchLawCorpusServiceSpecHelpers.raw_root.join(".commit_sha").read).to eq("new-sha")
    end
  end

  describe "#call — offline tolerance" do
    it "uses the cached corpus when the network fails but charter.xml exists on disk" do
      FetchLawCorpusServiceSpecHelpers.write_cached_charter

      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).and_raise(Faraday::ConnectionFailed.new("boom"))

      expect(described_class.new(run: nil, http: http).call).to eq(:cached_offline)
    end
  end

  # @lat: [[outbound-fetch-safety#An oversized download is stopped rather than refused afterwards]]
  describe "#call — size caps" do
    it "falls back to a cached corpus when the tarball is over the compressed-size cap" do
      stub_const("#{described_class}::MAX_TARBALL_BYTES", 16)
      FetchLawCorpusServiceSpecHelpers.write_cached_charter

      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).with(FetchLawCorpusService::COMMITS_URL)
        .and_return(instance_double(Faraday::Response, status: 200, body: {"sha" => "abc123"}.to_json))
      allow(http).to receive(:get).with(
        FetchLawCorpusService::TARBALL_URL,
        &FetchLawCorpusServiceSpecHelpers.tarball_stream(bytes: FetchLawCorpusServiceSpecHelpers.tarball_bytes)
      )

      expect(described_class.new(run: nil, http: http).call).to eq(:cached_offline)
    end

    it "raises StageError over the compressed-size cap when no cached corpus exists" do
      stub_const("#{described_class}::MAX_TARBALL_BYTES", 16)

      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).with(FetchLawCorpusService::COMMITS_URL)
        .and_return(instance_double(Faraday::Response, status: 200, body: {"sha" => "abc123"}.to_json))
      allow(http).to receive(:get).with(
        FetchLawCorpusService::TARBALL_URL,
        &FetchLawCorpusServiceSpecHelpers.tarball_stream(bytes: FetchLawCorpusServiceSpecHelpers.tarball_bytes)
      )

      expect { described_class.new(run: nil, http: http).call }
        .to raise_error(StageError, /tarball passed the 16-byte cap/)
    end

    # @lat: [[outbound-fetch-safety#A declared size is checked as well as the bytes that arrive]]
    it "refuses a response whose headers claim more than the cap, even when its bytes fit" do
      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).with(FetchLawCorpusService::COMMITS_URL)
        .and_return(instance_double(Faraday::Response, status: 200, body: {"sha" => "abc123"}.to_json))
      allow(http).to receive(:get).with(
        FetchLawCorpusService::TARBALL_URL,
        &FetchLawCorpusServiceSpecHelpers.tarball_stream(
          bytes: FetchLawCorpusServiceSpecHelpers.tarball_bytes,
          headers: {"content-length" => "999999999999"}
        )
      )

      expect { described_class.new(run: nil, http: http).call }
        .to raise_error(StageError, /tarball advertises 999999999999 bytes, over the \d+-byte cap/)
    end

    it "raises StageError when the expanded corpus is over the extracted-size cap" do
      stub_const("#{described_class}::MAX_EXTRACTED_BYTES", 16)

      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).with(FetchLawCorpusService::COMMITS_URL)
        .and_return(instance_double(Faraday::Response, status: 200, body: {"sha" => "abc123"}.to_json))
      allow(http).to receive(:get).with(
        FetchLawCorpusService::TARBALL_URL,
        &FetchLawCorpusServiceSpecHelpers.tarball_stream(bytes: FetchLawCorpusServiceSpecHelpers.tarball_bytes)
      )

      expect { described_class.new(run: nil, http: http).call }
        .to raise_error(StageError, /extracted corpus exceeds \d+ bytes/)
    end
  end

  describe "#call — hard failure" do
    it "raises StageError when the network fails and no cached corpus exists" do
      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).and_raise(Faraday::ConnectionFailed.new("boom"))

      expect { described_class.new(run: nil, http: http).call }.to raise_error(StageError, /no cached corpus/)
    end

    it "raises StageError when the tarball request returns a non-success status" do
      http = instance_double(Faraday::Connection)
      allow(http).to receive(:get).with(FetchLawCorpusService::COMMITS_URL)
        .and_return(instance_double(Faraday::Response, status: 200, body: {"sha" => "abc123"}.to_json))
      allow(http).to receive(:get).with(FetchLawCorpusService::TARBALL_URL)
        .and_return(instance_double(Faraday::Response, status: 503, body: ""))

      expect { described_class.new(run: nil, http: http).call }.to raise_error(StageError, /non-success status/)
    end
  end

  describe "#call — non-Baltimore jurisdiction rules" do
    let(:maryland_locale) { create(:sway_locale, :maryland) }
    let(:maryland_run) { create(:legislation_pipeline_run, sway_locale: maryland_locale) }
    let(:http) { instance_double(Faraday::Connection) }

    it "refuses to download Baltimore law-xml for Maryland" do
      expect { described_class.new(run: maryland_run, http: http).call }
        .to raise_error(StageError, /law corpus repository is not configured for maryland-maryland-united_states/)
    end

    it "raises StageError when law_rules engine is :unavailable" do
      manual_rules = instance_double(
        SwayLocale::JurisdictionRules,
        law_rules: {engine: :unavailable}
      )
      manual_locale = instance_double(
        SwayLocale,
        name: "manual-locale-united_states",
        jurisdiction_rules: manual_rules
      )
      manual_run = instance_double(LegislationPipelineRun, id: 88, effective_sway_locale: manual_locale)

      expect { described_class.new(run: manual_run, http: http).call }
        .to raise_error(StageError, "fetch_law_corpus: law acquisition is unavailable for manual-locale-united_states")
    end

    it "raises StageError for non-Baltimore engine without checking law_source" do
      custom_rules = instance_double(
        SwayLocale::JurisdictionRules,
        law_rules: {engine: :generic_rest}
      )
      expect(custom_rules.respond_to?(:law_source)).to be false
      custom_locale = instance_double(
        SwayLocale,
        name: "custom-locale",
        jurisdiction_rules: custom_rules
      )
      custom_run = instance_double(LegislationPipelineRun, id: 89, effective_sway_locale: custom_locale)

      expect { described_class.new(run: custom_run, http: http).call }
        .to raise_error(StageError, "fetch_law_corpus: law corpus repository is not configured for custom-locale (law source: generic_rest)")
    end
  end

  describe "#call — dynamic repository configuration" do
    it "reads repository and branch from law_rules and constructs target URLs" do
      custom_rules = instance_double(
        SwayLocale::JurisdictionRules,
        law_rules: {engine: :akoma_ntoso, repo: "custom-org/custom-law", branch: "dev"}
      )
      custom_locale = instance_double(
        SwayLocale,
        name: "custom-jurisdiction",
        jurisdiction_rules: custom_rules
      )
      custom_run = instance_double(LegislationPipelineRun, id: 99, effective_sway_locale: custom_locale)
      http = instance_double(Faraday::Connection)

      service = described_class.new(run: custom_run, http: http)
      expect(service.commits_url).to eq("https://api.github.com/repos/custom-org/custom-law/commits/dev")
      expect(service.tarball_url).to eq("https://github.com/custom-org/custom-law/archive/refs/heads/dev.tar.gz")

      allow(http).to receive(:get).with("https://api.github.com/repos/custom-org/custom-law/commits/dev")
        .and_return(instance_double(Faraday::Response, status: 200, body: {"sha" => "fed789"}.to_json))
      allow(http).to receive(:get).with(
        "https://github.com/custom-org/custom-law/archive/refs/heads/dev.tar.gz",
        &FetchLawCorpusServiceSpecHelpers.tarball_stream(bytes: FetchLawCorpusServiceSpecHelpers.tarball_bytes)
      )

      expect(service.call).to eq(:downloaded)
      expect(service.repo).to eq("custom-org/custom-law")
      expect(service.branch).to eq("dev")
    end

    it "defaults branch to 'main' when branch is blank or whitespace" do
      rules = instance_double(
        SwayLocale::JurisdictionRules,
        law_rules: {"engine" => "akoma_ntoso", "repo" => "open-law/dc", "branch" => "   "}
      )
      locale = instance_double(SwayLocale, name: "custom-dc", jurisdiction_rules: rules)
      http = instance_double(Faraday::Connection)
      service = described_class.new(sway_locale: locale, http: http)

      expect(service.branch).to eq("main")
      expect(service.commits_url).to eq("https://api.github.com/repos/open-law/dc/commits/main")
    end

    it "raises StageError when repo is empty string or whitespace" do
      ["", "   "].each do |empty_repo|
        rules = instance_double(
          SwayLocale::JurisdictionRules,
          law_rules: {"engine" => "akoma_ntoso", "repo" => empty_repo}
        )
        locale = instance_double(SwayLocale, name: "blank-repo-loc", jurisdiction_rules: rules)
        http = instance_double(Faraday::Connection)
        service = described_class.new(sway_locale: locale, http: http)

        expect { service.call }.to raise_error(
          StageError,
          "fetch_law_corpus: law corpus repository is not configured for blank-repo-loc (law source: akoma_ntoso)"
        )
      end
    end

    it "falls back to DEFAULT_REPO and DEFAULT_BRANCH when sway_locale is nil" do
      http = instance_double(Faraday::Connection)
      service = described_class.new(sway_locale: nil, http: http)
      expect(service.repo).to eq(described_class::DEFAULT_REPO)
      expect(service.branch).to eq(described_class::DEFAULT_BRANCH)
      expect(service.commits_url).to eq(described_class::COMMITS_URL)
      expect(service.tarball_url).to eq(described_class::TARBALL_URL)
    end
  end
end
