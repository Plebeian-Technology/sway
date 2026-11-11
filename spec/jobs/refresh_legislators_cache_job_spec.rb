# frozen_string_literal: true

require "rails_helper"

RSpec.describe RefreshLegislatorsCacheJob, type: :job do
  let(:pr_service_double) { instance_double(GitHubPrService) }

  # The result object every refresher hands back, here with nothing changed
  let(:empty_result) { LegislatorsCache::BaseRefresh::Result.new(changed_files: {}) }

  def make_result(files)
    LegislatorsCache::BaseRefresh::Result.new(changed_files: files)
  end

  before do
    allow(GitHubPrService).to receive(:new).and_return(pr_service_double)
    allow(pr_service_double).to receive(:open_pr)

    # @lat: [[error-reporting-in-tests#Why Sentry's methods are watched rather than the constant replaced]]
    allow(Sentry).to receive(:capture_exception)
    allow(Sentry).to receive(:capture_message)
  end

  # ---------------------------------------------------------------
  # (a) One failing locale must not take the others down
  # ---------------------------------------------------------------
  describe "per-locale error isolation" do
    # Three fake locales, each answering yes to exactly one "what kind am I" question
    let(:congress_locale) do
      sway_locale = instance_double(SwayLocale, name: "Congress")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :congress}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:maryland_locale) do
      sway_locale = instance_double(SwayLocale, name: "Maryland")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :open_states}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:baltimore_locale) do
      sway_locale = instance_double(SwayLocale, name: "Baltimore")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :baltimore}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:congress_instance) { instance_double(LegislatorsCache::BaseRefresh) }
    let(:open_states_instance) { instance_double(LegislatorsCache::BaseRefresh) }
    let(:baltimore_instance) { instance_double(LegislatorsCache::BaseRefresh) }

    before { allow(Sentry).to receive(:capture_message) }

    before do
      allow(SwayLocale).to receive(:find_each).and_yield(congress_locale)
        .and_yield(maryland_locale)
        .and_yield(baltimore_locale)
    end

    it "continues to other locales when one refresher raises, does not re-raise, calls Sentry once" do
      # Congress blows up. Maryland and Baltimore succeed with nothing changed, so no pull request.
      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(congress_locale, force: false)
        .and_return(congress_instance)
      allow(congress_instance).to receive(:call).and_raise(RuntimeError, "Congress API down")

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(maryland_locale, force: false)
        .and_return(open_states_instance)
      allow(open_states_instance).to receive(:call).and_return(empty_result)

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(baltimore_locale, force: false)
        .and_return(baltimore_instance)
      allow(baltimore_instance).to receive(:call).and_return(empty_result)

      expect { described_class.new.perform }.not_to raise_error

      # The loop kept going, so the other two locales still ran
      expect(open_states_instance).to have_received(:call)
      expect(baltimore_instance).to have_received(:call)

      expect(Sentry).to have_received(:capture_exception)
        .with(instance_of(RuntimeError), hash_including(extra: {locale: "Congress"}))
        .once
    end
  end

  # ---------------------------------------------------------------
  # (a2) Every attempted locale raising must not read as a quiet week
  # ---------------------------------------------------------------
  describe "total-failure detection" do
    let(:congress_locale) do
      sway_locale = instance_double(SwayLocale, name: "Congress")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :congress}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:maryland_locale) do
      sway_locale = instance_double(SwayLocale, name: "Maryland")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :open_states}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:baltimore_locale) do
      sway_locale = instance_double(SwayLocale, name: "Baltimore")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :baltimore}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:congress_instance) { instance_double(LegislatorsCache::BaseRefresh) }
    let(:open_states_instance) { instance_double(LegislatorsCache::BaseRefresh) }
    let(:baltimore_instance) { instance_double(LegislatorsCache::BaseRefresh) }

    it "reports the total failure to Sentry and still finishes, without skipping the per-locale reports" do
      allow(SwayLocale).to receive(:find_each).and_yield(congress_locale)
        .and_yield(maryland_locale)
        .and_yield(baltimore_locale)

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(congress_locale, force: false)
        .and_return(congress_instance)
      allow(congress_instance).to receive(:call).and_raise(RuntimeError, "Congress API down")

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(maryland_locale, force: false)
        .and_return(open_states_instance)
      allow(open_states_instance).to receive(:call).and_raise(RuntimeError, "OpenStates API down")

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(baltimore_locale, force: false)
        .and_return(baltimore_instance)
      allow(baltimore_instance).to receive(:call).and_raise(RuntimeError, "Legistar unreachable")

      expect { described_class.new.perform }.not_to raise_error

      expect(Sentry).to have_received(:capture_message)
        .with(RefreshLegislatorsCacheJob::ALL_LOCALES_FAILED_ALARM, hash_including(level: :error, extra: {attempted_locales: 3}))

      expect(Sentry).to have_received(:capture_exception)
        .with(instance_of(RuntimeError), hash_including(extra: {locale: "Congress"}))
      expect(Sentry).to have_received(:capture_exception)
        .with(instance_of(RuntimeError), hash_including(extra: {locale: "Maryland"}))
      expect(Sentry).to have_received(:capture_exception)
        .with(instance_of(RuntimeError), hash_including(extra: {locale: "Baltimore"}))
      expect(pr_service_double).not_to have_received(:open_pr)
    end

    it "finishes successfully when at least one attempted locale succeeds, even though others raised" do
      allow(SwayLocale).to receive(:find_each).and_yield(congress_locale)
        .and_yield(maryland_locale)
        .and_yield(baltimore_locale)

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(congress_locale, force: false)
        .and_return(congress_instance)
      allow(congress_instance).to receive(:call).and_raise(RuntimeError, "Congress API down")

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(maryland_locale, force: false)
        .and_return(open_states_instance)
      allow(open_states_instance).to receive(:call).and_raise(RuntimeError, "OpenStates API down")

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(baltimore_locale, force: false)
        .and_return(baltimore_instance)
      allow(baltimore_instance).to receive(:call).and_return(empty_result)

      expect { described_class.new.perform }.not_to raise_error

      expect(Sentry).not_to have_received(:capture_message)
    end

    it "finishes successfully when no locale declares a refresher, since none of them were attempted" do
      chicago = instance_double(SwayLocale, name: "chicago-illinois-united_states")
      allow(chicago).to receive(:declared_jurisdiction_rules).and_return(nil)

      allow(SwayLocale).to receive(:find_each).and_yield(chicago)

      expect { described_class.new.perform }.not_to raise_error

      expect(Sentry).not_to have_received(:capture_message)
    end
  end

  # ---------------------------------------------------------------
  # (b) Two changed locales share a single pull request
  # ---------------------------------------------------------------
  describe "combined PR with two changed locales" do
    let(:congress_locale) do
      sway_locale = instance_double(SwayLocale, name: "Congress")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :congress}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:maryland_locale) do
      sway_locale = instance_double(SwayLocale, name: "Maryland")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :open_states}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:congress_instance) { instance_double(LegislatorsCache::BaseRefresh) }
    let(:open_states_instance) { instance_double(LegislatorsCache::BaseRefresh) }

    before do
      allow(SwayLocale).to receive(:find_each).and_yield(congress_locale)
        .and_yield(maryland_locale)

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(congress_locale, force: false)
        .and_return(congress_instance)
      allow(congress_instance).to receive(:call)
        .and_return(make_result({"seeds/congress.json" => '{"congress":true}'}))

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(maryland_locale, force: false)
        .and_return(open_states_instance)
      allow(open_states_instance).to receive(:call)
        .and_return(make_result({"seeds/maryland.json" => '{"maryland":true}'}))
    end

    it "calls open_pr exactly once with merged files from both changed locales" do
      described_class.new.perform

      expect(pr_service_double).to have_received(:open_pr).once do |branch:, title:, body:, files:|
        expect(files).to include(
          "seeds/congress.json" => '{"congress":true}',
          "seeds/maryland.json" => '{"maryland":true}'
        )
        expect(branch).to match(/seeds\/refresh-legislators-\d{8}/)
      end
    end
  end

  # ---------------------------------------------------------------
  # (c) Nothing changed: no pull request opened, and the skip is logged
  # ---------------------------------------------------------------
  describe "no-change path" do
    let(:congress_locale) do
      sway_locale = instance_double(SwayLocale, name: "Congress")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :congress}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:congress_instance) { instance_double(LegislatorsCache::BaseRefresh) }

    before do
      allow(SwayLocale).to receive(:find_each).and_yield(congress_locale)

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(congress_locale, force: false)
        .and_return(congress_instance)
      allow(congress_instance).to receive(:call).and_return(empty_result)
    end

    it "does not call open_pr and logs skip message" do
      expect(Rails.logger).to receive(:info).with(/no.*change.*skip.*pr/i).at_least(:once)

      described_class.new.perform

      expect(pr_service_double).not_to have_received(:open_pr)
    end
  end

  # @lat: [[refresh-legislators-cache-job-design#Why a pull-request failure bubbles up instead of being rescued]]
  describe "PR-service failure propagation" do
    let(:congress_locale) do
      sway_locale = instance_double(SwayLocale, name: "Congress")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :congress}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:congress_instance) { instance_double(LegislatorsCache::BaseRefresh) }

    before do
      allow(SwayLocale).to receive(:find_each).and_yield(congress_locale)

      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(congress_locale, force: false)
        .and_return(congress_instance)
      allow(congress_instance).to receive(:call)
        .and_return(make_result({"seeds/congress.json" => '{"congress":true}'}))
    end

    it "propagates an Octokit::UnprocessableEntity raised by open_pr (no outer rescue)" do
      allow(pr_service_double).to receive(:open_pr).and_raise(Octokit::UnprocessableEntity)

      expect { described_class.new.perform }.to raise_error(Octokit::UnprocessableEntity)

      # The pull-request failure does not travel the per-locale Sentry path.
      expect(Sentry).not_to have_received(:capture_exception)
    end
  end

  # @lat: [[refresh-legislators-cache-job-design#Why a locale that declares no refresher is fetched by nothing]]
  describe "a locale that declares no refresher" do
    let(:chicago) do
      sway_locale = instance_double(SwayLocale, name: "chicago-illinois-united_states")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(nil)
      sway_locale
    end

    before do
      allow(SwayLocale).to receive(:find_each).and_yield(chicago)
      allow(LegislatorsCache::BaseRefresh).to receive(:new)
    end

    it "fetches nothing for it, and opens no pull request" do
      described_class.new.perform

      expect(LegislatorsCache::BaseRefresh).not_to have_received(:new)
      expect(pr_service_double).not_to have_received(:open_pr)
    end
  end

  # ---------------------------------------------------------------
  # (f) The Sentry cron monitor
  # ---------------------------------------------------------------
  describe "Sentry cron monitor" do
    let(:congress_locale) do
      sway_locale = instance_double(SwayLocale, name: "Congress")
      allow(sway_locale).to receive(:declared_jurisdiction_rules).and_return(
        instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :congress}, roster_retrieval: nil)
      )
      sway_locale
    end

    let(:congress_instance) { instance_double(LegislatorsCache::BaseRefresh) }

    before do
      allow(Sentry).to receive(:capture_check_in).and_return("check-in-id")

      allow(SwayLocale).to receive(:find_each).and_yield(congress_locale)
      allow(LegislatorsCache::BaseRefresh).to receive(:new)
        .with(congress_locale, force: false)
        .and_return(congress_instance)
      allow(congress_instance).to receive(:call).and_return(empty_result)
    end

    it "sets an explicit monitor slug, different from the value the library would derive from the class name" do
      derived_slug = described_class.name.gsub("::", "-").downcase

      expect(described_class.sentry_monitor_slug).to eq("refresh-legislators-cache")
      expect(described_class.sentry_monitor_slug).not_to eq(derived_slug)
    end

    it "keeps the slug at 50 characters or fewer" do
      expect(described_class.sentry_monitor_slug.length).to be <= 50
    end

    it "sets the missed-check-in margin to 60 minutes" do
      expect(described_class.sentry_monitor_config.checkin_margin).to eq(60)
    end

    it "sets the monitor's crontab to the same schedule as config/recurring.yml's production entry" do
      recurring = YAML.load_file(Rails.root.join("config", "recurring.yml"))
      expected_schedule = recurring.fetch("production").fetch("refresh_legislators_cache").fetch("schedule")

      expect(described_class.sentry_monitor_config.schedule.value).to eq(expected_schedule)
    end

    it "sends an in-progress check-in and then a successful check-in on a healthy run, both against the monitor slug" do
      described_class.new.perform

      expect(Sentry).to have_received(:capture_check_in)
        .with(described_class.sentry_monitor_slug, :in_progress, hash_including(monitor_config: an_instance_of(Sentry::Cron::MonitorConfig)))
      expect(Sentry).to have_received(:capture_check_in)
        .with(described_class.sentry_monitor_slug, :ok, hash_including(monitor_config: an_instance_of(Sentry::Cron::MonitorConfig)))
    end

    # The four unnoticed Sundays all died here, past the
    # per-locale rescue, on the pull-request call.
    it "sends a failed check-in when the run raises, and still lets the error out" do
      allow(congress_instance).to receive(:call)
        .and_return(make_result({"seeds/congress.json" => '{"congress":true}'}))
      allow(pr_service_double).to receive(:open_pr).and_raise(Octokit::UnprocessableEntity)

      expect { described_class.new.perform }.to raise_error(Octokit::UnprocessableEntity)

      expect(Sentry).to have_received(:capture_check_in)
        .with(described_class.sentry_monitor_slug, :error, hash_including(monitor_config: an_instance_of(Sentry::Cron::MonitorConfig)))
    end
  end

  it "delegates dynamically to BaseRefresh for configured locales" do
    allow(LegislatorsCache::BaseRefresh).to receive(:new).and_return(instance_double(LegislatorsCache::BaseRefresh, call: empty_result))
    expect { described_class.new.perform }.not_to raise_error
  end

  it "skips a configured manual locale with unavailable roster refresher without error or network requests" do
    manual_locale = instance_double(SwayLocale, name: "Annapolis")
    allow(manual_locale).to receive(:declared_jurisdiction_rules).and_return(
      instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :unavailable}, roster_retrieval: nil)
    )
    congress_locale = instance_double(SwayLocale, name: "Congress")
    allow(congress_locale).to receive(:declared_jurisdiction_rules).and_return(
      instance_double(SwayLocale::JurisdictionRules, roster_rules: {engine: :congress}, roster_retrieval: nil)
    )
    allow(SwayLocale).to receive(:find_each).and_yield(manual_locale).and_yield(congress_locale)
    allow(LegislatorsCache::BaseRefresh).to receive(:new).with(congress_locale, force: false).and_return(double(call: make_result({})))

    allow(SwayLogging).to receive(:info)
    expect(SwayLogging).to receive(:info).with(
      "refresh_legislators_cache.unavailable_refresher",
      hash_including(sway_locale: manual_locale.name)
    )

    expect { described_class.new.perform }.not_to raise_error
    expect(LegislatorsCache::BaseRefresh).to have_received(:new).with(congress_locale, force: false)
  end

  it "skips locales with retrieval set to unavailable or curated under decoupled rules" do
    curated_locale = instance_double(SwayLocale, name: "CuratedLocale")
    rules = instance_double(
      SwayLocale::JurisdictionRules,
      roster_rules: {retrieval: "curated", engine: "open_states"},
      roster_retrieval: "curated"
    )
    allow(curated_locale).to receive(:declared_jurisdiction_rules).and_return(rules)
    allow(SwayLocale).to receive(:find_each).and_yield(curated_locale)

    expect(LegislatorsCache::BaseRefresh).not_to receive(:new).with(curated_locale, anything)
    described_class.new.perform
  end

  describe "end-to-end integration across configured locales" do
    let!(:baltimore) { create(:sway_locale, :baltimore) }
    let!(:annapolis) do
      create(:sway_locale, city: "annapolis", region_name: "maryland", state: "maryland", country: "united_states")
    end
    let!(:maryland) { create(:sway_locale, :maryland) }
    let!(:congress) { create(:sway_locale, :congress) }

    before do
      md_path = Rails.root.join("tmp", "legislators_cache_#{maryland.reversed_name}.json")
      cg_path = Rails.root.join("tmp", "legislators_cache_#{congress.reversed_name}.json")
      FileUtils.rm_f([md_path, cg_path])
      allow(EnvSecret).to receive(:open_states_api_key!).and_return("test_open_states_key")
      allow(EnvSecret).to receive(:congress_gov_api_key!).and_return("test_congress_gov_key")
      allow_any_instance_of(LegislatorsCache::BaseRefresh).to receive(:canonical_seed_path).and_return(Rails.root.join("tmp", "nonexistent_canonical_seed.json").to_s)
      allow_any_instance_of(LegislatorsCache::BaseRefresh).to receive(:upload_json_to_gcs)
    end

    after do
      md_path = Rails.root.join("tmp", "legislators_cache_#{maryland.reversed_name}.json")
      cg_path = Rails.root.join("tmp", "legislators_cache_#{congress.reversed_name}.json")
      FileUtils.rm_f([md_path, cg_path])
    end

    it "refreshes API locales successfully without total-failure alarm and produces valid preparer JSON" do
      require Rails.root.join("db", "seeds", "seed_preparers", "legislators", "open_states")
      require Rails.root.join("db", "seeds", "seed_preparers", "legislators", "congress_dot_gov")

      open_states_payload = {
        results: [
          {
            "id" => "ocd-person/md-001",
            "name" => "Delegate Smith",
            "given_name" => "Delegate",
            "family_name" => "Smith",
            "party" => "Democratic",
            "current_role" => {"title" => "Delegate", "district" => "42A", "org_classification" => "lower"},
            "jurisdiction" => {"name" => "Maryland"},
            "image" => "https://example.com/smith.jpg",
            "email" => "smith@example.test",
            "openstates_url" => "https://openstates.org/person/smith/"
          }
        ],
        pagination: {page: 1, per_page: 50, max_page: 1}
      }.to_json

      congress_payload = {
        members: [
          {
            "bioguideId" => "H000001",
            "name" => "Jones, Sarah",
            "partyName" => "Republican",
            "state" => "Maryland",
            "district" => 3,
            "depiction" => {"imageUrl" => "https://example.com/jones.jpg"},
            "terms" => {"item" => [{"chamber" => "House of Representatives", "startYear" => 2023, "district" => 3, "stateCode" => "MD"}]},
            "updateDate" => "2026-10-14"
          }
        ],
        pagination: {count: 1}
      }.to_json

      stub_request(:get, %r{https://v3\.openstates\.org/people})
        .with(headers: {"X-Api-Key" => "test_open_states_key"})
        .to_return(status: 200, body: open_states_payload, headers: {"Content-Type" => "application/json"})

      stub_request(:get, %r{https://api\.congress\.gov/v3/member})
        .to_return(status: 200, body: congress_payload, headers: {"Content-Type" => "application/json"})

      stub_request(:get, %r{https://unitedstates\.github\.io/congress-legislators/})
        .to_return(status: 200, body: [].to_json, headers: {"Content-Type" => "application/json"})

      described_class.new.perform

      expect(Sentry).not_to have_received(:capture_exception)
      expect(Sentry).not_to have_received(:capture_message)
        .with(described_class::ALL_LOCALES_FAILED_ALARM, any_args)

      md_path = Rails.root.join("tmp", "legislators_cache_#{maryland.reversed_name}.json")
      expect(File.exist?(md_path)).to be(true)
      md_json = JSON.parse(File.read(md_path)).first
      md_prep = SeedPreparers::Legislators::OpenStates.new(md_json, maryland)
      expect(md_prep.external_id).to eq("ocd-person/md-001")
      expect(md_prep.title).to eq("Delegate")
      expect(md_prep.region_code).to eq("MD")

      cg_path = Rails.root.join("tmp", "legislators_cache_#{congress.reversed_name}.json")
      expect(File.exist?(cg_path)).to be(true)
      cg_json = JSON.parse(File.read(cg_path)).first
      cg_prep = SeedPreparers::Legislators::CongressDotGov.new(cg_json, congress)
      expect(cg_prep.external_id).to eq("H000001")
      expect(cg_prep.first_name).to eq("Sarah")
      expect(cg_prep.last_name).to eq("Jones")
      expect(cg_prep.region_code).to eq("MD")
    end
  end
end
