# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislation-path-root-resolution#Test isolation]]
# SWAY_TEST_DATABASE_DIR and TEST_ENV_NUMBER stay ENV-set here deliberately: they are
# harness isolation plumbing (verify.sh, parallel_tests), not Sway::Settings::Legislation names.
module LegislationPathsSpecHelpers
  HARNESS_ENV_KEYS = %w[SWAY_TEST_DATABASE_DIR TEST_ENV_NUMBER].freeze
end

# @lat: [[legislation-path-root-resolution#Test isolation]]
# Cleared here so "default (no env)" below stays accurate even when this file runs under an isolated rspec invocation.
RSpec.describe Legislation::Paths do
  around do |example|
    # Built by hand rather than with to_h: a two-element array literal in a
    # block reads as a plain array to the type checker, not as a pair.
    original = {} #: Hash[String, String?]
    LegislationPathsSpecHelpers::HARNESS_ENV_KEYS.each { |k| original[k] = ENV[k] }
    begin
      LegislationPathsSpecHelpers::HARNESS_ENV_KEYS.each { |k| ENV.delete(k) }
      example.run
    ensure
      original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end

  describe "default (no env) — repo-relative, dev/test parity" do
    it "roots every stage under Rails.root/legislation" do
      with_app_config(:legislation,
        legislation_root: nil,
        legislation_bills_raw_root: nil,
        legislation_bills_text_root: nil,
        legislation_hearings_root: nil,
        legislation_law_root: nil,
        legislation_diffs_root: nil,
        legislation_attachments_root: nil) do
        expect(described_class.root).to eq(Rails.root.join("legislation"))
        expect(described_class.bills_raw).to eq(Rails.root.join("legislation", "bills", "raw"))
        expect(described_class.bills_text).to eq(Rails.root.join("legislation", "bills", "text"))
        expect(described_class.hearings).to eq(Rails.root.join("legislation", "hearings"))
        expect(described_class.law).to eq(Rails.root.join("legislation", "law"))
        expect(described_class.diffs).to eq(Rails.root.join("legislation", "diffs"))
        expect(described_class.attachments).to eq(Rails.root.join("legislation", "attachments"))
      end
    end
  end

  describe "LEGISLATION_ROOT — the production single knob" do
    it "relocates every stage under the absolute base (mirrors /rails/storage/legislation)" do
      with_app_config(:legislation, legislation_root: "/rails/storage/legislation") do
        expect(described_class.root).to eq(Pathname.new("/rails/storage/legislation"))
        expect(described_class.bills_raw).to eq(Pathname.new("/rails/storage/legislation/bills/raw"))
        expect(described_class.bills_text).to eq(Pathname.new("/rails/storage/legislation/bills/text"))
        expect(described_class.hearings).to eq(Pathname.new("/rails/storage/legislation/hearings"))
        expect(described_class.law).to eq(Pathname.new("/rails/storage/legislation/law"))
        expect(described_class.diffs).to eq(Pathname.new("/rails/storage/legislation/diffs"))
        expect(described_class.attachments).to eq(Pathname.new("/rails/storage/legislation/attachments"))
      end
    end
  end

  # @lat: [[legislation-path-root-resolution#Test isolation]]
  describe "SWAY_TEST_DATABASE_DIR / TEST_ENV_NUMBER — the same isolation axes as the test database" do
    it "roots under the run's isolation directory when SWAY_TEST_DATABASE_DIR is set and legislation_root is not" do
      with_app_config(:legislation, legislation_root: nil) do
        ENV["SWAY_TEST_DATABASE_DIR"] = "/testdb"

        expect(described_class.root).to eq(Pathname.new("/testdb/legislation"))
      end
    end

    it "gives two TEST_ENV_NUMBER values two different directories, so each worker owns one writer" do
      with_app_config(:legislation, legislation_root: nil) do
        ENV["SWAY_TEST_DATABASE_DIR"] = "/testdb"
        ENV["TEST_ENV_NUMBER"] = "2"

        expect(described_class.root).to eq(Pathname.new("/testdb/legislation2"))
      end
    end

    it "still lets an explicit legislation_root win over the isolation directory (production sets it)" do
      with_app_config(:legislation, legislation_root: "/rails/storage/legislation") do
        ENV["SWAY_TEST_DATABASE_DIR"] = "/testdb"

        expect(described_class.root).to eq(Pathname.new("/rails/storage/legislation"))
      end
    end

    it "falls back to today's repo-relative path when neither isolation variable is set" do
      with_app_config(:legislation, legislation_root: nil) do
        expect(described_class.root).to eq(Rails.root.join("legislation"))
      end
    end
  end

  describe "per-stage overrides take precedence over legislation_root" do
    it "uses an absolute per-stage override verbatim" do
      with_app_config(:legislation,
        legislation_root: "/rails/storage/legislation",
        legislation_bills_raw_root: "/tmp/custom/raw") do
        expect(described_class.bills_raw).to eq(Pathname.new("/tmp/custom/raw"))
        # Unrelated stages still follow the base root.
        expect(described_class.hearings).to eq(Pathname.new("/rails/storage/legislation/hearings"))
      end
    end

    it "resolves a relative per-stage override under Rails.root (spec-isolation semantics)" do
      with_app_config(:legislation, legislation_diffs_root: "tmp/test_artifacts/diffs") do
        expect(described_class.diffs).to eq(Rails.root.join("tmp", "test_artifacts", "diffs"))
      end
    end

    # @lat: [[legislation-path-root-resolution#Where the root comes from]]
    it "falls back to the root when a per-stage override is set to an empty string, rather than resolving to the application root" do
      with_app_config(:legislation,
        legislation_root: "/rails/storage/legislation",
        legislation_diffs_root: "") do
        expect(described_class.diffs).to eq(Pathname.new("/rails/storage/legislation/diffs"))
      end
    end
  end

  describe "LEGISLATION_ATTACHMENTS_ROOT — attachments-area override" do
    it "uses an absolute legislation_attachments_root override verbatim" do
      with_app_config(:legislation, legislation_attachments_root: "/tmp/custom/attachments") do
        expect(described_class.attachments).to eq(Pathname.new("/tmp/custom/attachments"))
      end
    end

    it "resolves a relative legislation_attachments_root override under Rails.root" do
      with_app_config(:legislation, legislation_attachments_root: "tmp/test_artifacts/attachments") do
        expect(described_class.attachments).to eq(Rails.root.join("tmp", "test_artifacts", "attachments"))
      end
    end
  end

  # Every per-bill path is built HERE, from a cleaned-up id. Pathname#join
  # does NOT collapse dot-dot, so a hand-edited metadata.json id could
  # create a directory anywhere.
  describe "external_id path coercion (A1-CR-02)" do
    describe ".external_id_segment!" do
      it "returns a conforming id unchanged" do
        expect(described_class.external_id_segment!("24-0599")).to eq("24-0599")
      end

      # Production holds two ids that break the format, both starting with a
      # TAB (bills 58/59), both dormant — no file path was ever built from
      # them, so trimming the whitespace risks no collision.
      it "strips surrounding whitespace, including the leading TAB production carries" do
        expect(described_class.external_id_segment!("\t24-0599")).to eq("24-0599")
        expect(described_class.external_id_segment!("  24-0592 \n")).to eq("24-0592")
      end

      it "accepts the shapes the three supported locales actually use" do
        %w[24-0599 HB1234 SB567 hr815 S.J.Res.12 CB_23-0312].each do |id|
          expect(described_class.external_id_segment!(id)).to eq(id)
        end
      end

      [
        ["a parent-directory escape", "../../../../rails/config/pwned"],
        ["a bare parent reference", ".."],
        ["an embedded parent reference", "24-0599/../../etc"],
        ["an absolute path", "/etc/passwd"],
        ["a nested path segment", "24-0599/nested"],
        ["a backslash segment", "24-0599\\nested"],
        ["a NUL byte", "24-0599\0.json"],
        ["a query-string smuggle", "1?override=bar"],
        ["a leading dot (hidden file)", ".ssh"],
        ["a glob metacharacter", "24-*"],
        ["an empty string", ""],
        ["whitespace only", "   "],
        ["nil", nil]
      ].each do |label, value|
        it "refuses #{label}" do
          expect { described_class.external_id_segment!(value) }
            .to raise_error(Legislation::Paths::UnsafeExternalIdError)
        end
      end

      it "refuses an id longer than the 64-character bound" do
        expect { described_class.external_id_segment!("A" * 65) }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
      end

      it "accepts an id exactly at the 64-character bound" do
        expect(described_class.external_id_segment!("A" * 64)).to eq("A" * 64)
      end

      it "does not echo an unbounded value into the error message" do
        expect { described_class.external_id_segment!("../" * 500) }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError) { |e|
            expect(e.message.length).to be < 300
          }
      end
    end

    # The version that returns nil instead of raising, like
    # coerce_attachment_id vs coerce_matter_id!. Asking is there an artifact
    # wants no for an unnameable id, not a 500.
    describe ".external_id_segment" do
      it "returns the coerced segment when usable" do
        expect(described_class.external_id_segment("\t24-0599")).to eq("24-0599")
      end

      it "returns nil rather than raising when unusable" do
        expect(described_class.external_id_segment("../../etc")).to be_nil
        expect(described_class.external_id_segment(nil)).to be_nil
      end
    end

    describe "the per-bill builders" do
      around do |example|
        with_app_config(:legislation, legislation_root: "/tmp/legislation-spec") { example.run }
      end

      let(:sway_locale) { "baltimore-maryland-united_states" }

      it "builds every artifact path under its stage root, inside its sway_locale" do
        expect(described_class.bill_artifact_dir("24-0599", sway_locale: sway_locale))
          .to eq(Pathname.new("/tmp/legislation-spec/bills/raw/baltimore-maryland-united_states/24-0599"))
        expect(described_class.bill_pdf_glob("24-0599", sway_locale: sway_locale))
          .to eq("/tmp/legislation-spec/bills/raw/baltimore-maryland-united_states/24-0599/*.pdf")
        expect(described_class.bill_metadata_file("24-0599", sway_locale: sway_locale))
          .to eq(Pathname.new("/tmp/legislation-spec/bills/raw/baltimore-maryland-united_states/24-0599/metadata.json"))
        expect(described_class.bill_text_file("24-0599", sway_locale: sway_locale))
          .to eq(Pathname.new("/tmp/legislation-spec/bills/text/baltimore-maryland-united_states/24-0599.md"))
        expect(described_class.hearings_file("24-0599", sway_locale: sway_locale))
          .to eq(Pathname.new("/tmp/legislation-spec/hearings/baltimore-maryland-united_states/24-0599.json"))
        expect(described_class.diff_json_file("24-0599", sway_locale: sway_locale))
          .to eq(Pathname.new("/tmp/legislation-spec/diffs/baltimore-maryland-united_states/24-0599.json"))
        expect(described_class.diff_markdown_file("24-0599", sway_locale: sway_locale))
          .to eq(Pathname.new("/tmp/legislation-spec/diffs/baltimore-maryland-united_states/24-0599.md"))
        expect(described_class.attachment_dir(sway_locale: sway_locale))
          .to eq(Pathname.new("/tmp/legislation-spec/attachments/baltimore-maryland-united_states"))
      end

      # THE COLLISION THIS KEY EXISTS TO STOP: bills are unique on
      # (external_id, sway_locale_id) together, so one external_id can
      # legally exist in two jurisdictions.
      it "gives two jurisdictions sharing an external_id different paths" do
        baltimore = described_class.hearings_file("25-0064", sway_locale: "baltimore-maryland-united_states")
        other = described_class.hearings_file("25-0064", sway_locale: "annapolis-maryland-united_states")

        expect(baltimore).not_to eq(other)
      end

      it "refuses a traversal sway_locale from every builder" do
        traversal = "../../../../rails/config/pwned"

        expect { described_class.bill_artifact_dir("24-0599", sway_locale: traversal) }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
        expect { described_class.hearings_file("24-0599", sway_locale: traversal) }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
        expect { described_class.attachment_dir(sway_locale: traversal) }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
      end

      # THE POINT. Every builder has to refuse, or there is a gap — and the
      # recurring mistake in this area is a correct fix applied at one call site
      # when several exist.
      it "refuses a traversal id from EVERY builder, not just the ones the review named" do
        traversal = "../../../../rails/config/pwned"

        expect { described_class.bill_artifact_dir(traversal, sway_locale: "baltimore-maryland-united_states") }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
        expect { described_class.bill_pdf_glob(traversal, sway_locale: "baltimore-maryland-united_states") }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
        expect { described_class.bill_metadata_file(traversal, sway_locale: "baltimore-maryland-united_states") }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
        expect { described_class.bill_text_file(traversal, sway_locale: "baltimore-maryland-united_states") }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
        expect { described_class.hearings_file(traversal, sway_locale: "baltimore-maryland-united_states") }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
        expect { described_class.diff_json_file(traversal, sway_locale: "baltimore-maryland-united_states") }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
        expect { described_class.diff_markdown_file(traversal, sway_locale: "baltimore-maryland-united_states") }
          .to raise_error(Legislation::Paths::UnsafeExternalIdError)
      end

      it "keeps every built path inside its stage root even for a whitespace-padded id" do
        dir = described_class.bill_artifact_dir("\t24-0599 ", sway_locale: " baltimore-maryland-united_states\n")

        expect(dir.to_s).to start_with("/tmp/legislation-spec/bills/raw/")
        expect(dir.cleanpath.to_s)
          .to eq("/tmp/legislation-spec/bills/raw/baltimore-maryland-united_states/24-0599")
      end
    end
  end

  # File names arrive from Legistar inside JSON, and the pipeline joins them
  # onto a directory. This is the one place that cleans them.
  describe ".upstream_file_name" do
    it "keeps an ordinary name unchanged" do
      expect(described_class.upstream_file_name("BCFD 25-0064.pdf")).to eq("BCFD 25-0064.pdf")
    end

    it "drops the directory half of a name that carries one" do
      expect(described_class.upstream_file_name("../../etc/passwd")).to eq("passwd")
    end

    # A NUL is valid UTF-8, so the encoding scrub keeps it, and File.basename
    # raises ArgumentError on it. That raise is not a BillProcessingError, so
    # it used to cost every remaining bill in the run.
    it "removes a NUL byte rather than raising on it" do
      expect(described_class.upstream_file_name("report\u0000.pdf")).to eq("report.pdf")
    end

    it "still recognises the extension once the NUL is gone" do
      expect(described_class.upstream_file_name("report.pdf\u0000")).to eq("report.pdf")
    end

    # File.basename hands both of these straight back, and every caller joins
    # the result onto a directory.
    it "refuses the parent directory" do
      expect(described_class.upstream_file_name("..")).to be_nil
    end

    it "refuses the current directory" do
      expect(described_class.upstream_file_name(".")).to be_nil
    end

    it "returns nil for a name that is nothing but a NUL" do
      expect(described_class.upstream_file_name("\u0000")).to be_nil
    end

    it "returns nil for a value that is not a string" do
      expect(described_class.upstream_file_name(42)).to be_nil
    end

    it "returns nil for nil" do
      expect(described_class.upstream_file_name(nil)).to be_nil
    end
  end

  describe ".law" do
    around do |example|
      Dir.mktmpdir("legislation-law-spec") do |dir|
        with_app_config(:legislation, legislation_law_root: dir) do
          example.run
        end
      end
    end

    it "does not respond to .baltimore_locale?" do
      expect(described_class).not_to respond_to(:baltimore_locale?)
    end

    it "responds to .legacy_path_fallback?" do
      expect(described_class).to respond_to(:legacy_path_fallback?)
    end

    context "when sway_locale has legacy_path_fallback: true" do
      it "returns base when the scoped directory does not exist and base exists" do
        locale = instance_double(
          SwayLocale,
          name: "baltimore-maryland-united_states",
          to_s: "baltimore-maryland-united_states",
          jurisdiction_rules: instance_double(SwayLocale::JurisdictionRules, legacy_path_fallback?: true)
        )
        base = described_class.law
        FileUtils.mkdir_p(base)
        scoped = base.join("baltimore-maryland-united_states")
        expect(scoped).not_to exist

        expect(described_class.law(sway_locale: locale)).to eq(base)
      end

      it "returns base for any locale with legacy_path_fallback: true, not hardcoded to Baltimore" do
        custom_locale = instance_double(
          SwayLocale,
          name: "custom_city-maryland-united_states",
          to_s: "custom_city-maryland-united_states",
          city: "custom_city",
          region_name: "maryland",
          state: "maryland",
          jurisdiction_rules: instance_double(SwayLocale::JurisdictionRules, legacy_path_fallback?: true)
        )
        base = described_class.law
        FileUtils.mkdir_p(base)
        scoped = base.join("custom_city-maryland-united_states")
        expect(scoped).not_to exist

        expect(described_class.law(sway_locale: custom_locale)).to eq(base)
      end

      it "returns base for string slug 'baltimore-maryland-united_states' when scoped does not exist and base exists" do
        base = described_class.law
        FileUtils.mkdir_p(base)
        scoped = base.join("baltimore-maryland-united_states")
        expect(scoped).not_to exist

        expect(described_class.law(sway_locale: "baltimore-maryland-united_states")).to eq(base)
      end

      it "returns scoped when the scoped directory exists" do
        locale = instance_double(
          SwayLocale,
          name: "baltimore-maryland-united_states",
          to_s: "baltimore-maryland-united_states",
          jurisdiction_rules: instance_double(SwayLocale::JurisdictionRules, legacy_path_fallback?: true)
        )
        base = described_class.law
        scoped = base.join("baltimore-maryland-united_states")
        FileUtils.mkdir_p(scoped)

        expect(described_class.law(sway_locale: locale)).to eq(scoped)
      end
    end

    context "when sway_locale has legacy_path_fallback false or not set" do
      it "returns scoped directory regardless of directory existence" do
        locale = instance_double(
          SwayLocale,
          name: "annapolis-maryland-united_states",
          to_s: "annapolis-maryland-united_states",
          city: "annapolis",
          region_name: "maryland",
          state: "maryland",
          jurisdiction_rules: instance_double(SwayLocale::JurisdictionRules, legacy_path_fallback?: false)
        )
        base = described_class.law
        FileUtils.mkdir_p(base)
        scoped = base.join("annapolis-maryland-united_states")
        expect(scoped).not_to exist

        expect(described_class.law(sway_locale: locale)).to eq(scoped)
      end

      it "returns scoped for non-fallback string slugs even when base exists and scoped does not" do
        base = described_class.law
        FileUtils.mkdir_p(base)
        scoped = base.join("maryland-maryland-united_states")
        expect(scoped).not_to exist

        expect(described_class.law(sway_locale: "maryland-maryland-united_states")).to eq(scoped)
      end

      it "raises UnsafeExternalIdError in .law for path traversal or blank slug strings" do
        expect { described_class.law(sway_locale: "") }.to raise_error(Legislation::Paths::UnsafeExternalIdError)
        expect { described_class.law(sway_locale: "   ") }.to raise_error(Legislation::Paths::UnsafeExternalIdError)
        expect { described_class.law(sway_locale: "../../etc/passwd") }.to raise_error(Legislation::Paths::UnsafeExternalIdError)
      end
    end
  end
end
