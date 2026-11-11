# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Eval::PromptDump do
  # Both roots are redirected into a per-example temporary directory. Without
  # this the dump writes into the checkout's own untracked legislation/ tree,
  # where one example's files are visible to the next.
  around do |example|
    Dir.mktmpdir do |diffs|
      Dir.mktmpdir do |dumps|
        with_app_config(
          :legislation, legislation_diffs_root: diffs, legislation_prompt_dumps_root: dumps
        ) { example.run }
      end
    end
  end

  let(:sway_locale) { create(:sway_locale, city: "Baltimore", state: "Maryland", country: "United States") }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "HB9999",
      title: "An act concerning civic engagement"
    )
  end

  before do
    bill.create_bill_llm_provisioning!(
      extracted_testimony: "ORG X supports the bill because it protects tenants.",
      supplemental_testimony: "ORG Y opposes the bill's inspection cadence."
    )
  end

  describe ".normalize_delimiters" do
    it "replaces every registered prefix's random 16-hex suffix with a fixed placeholder" do
      text = Llm::UntrustedTextBlock::PREFIXES.each_value.map { |prefix| "<#{prefix}-#{SecureRandom.hex(8)}>" }.join("\n")

      normalized = described_class.normalize_delimiters(text)

      Llm::UntrustedTextBlock::PREFIXES.each_value do |prefix|
        expect(normalized).to include("<#{prefix}-<16-hex>>")
      end
      expect(normalized).not_to match(/-[0-9a-f]{16}>/)
    end

    it "iterates the PREFIXES registry rather than a hard-coded list" do
      expect(described_class.method(:normalize_delimiters).source_location).not_to be_nil
      # Every registered prefix must be replaceable, including one added after
      # this file was written — proven by asserting on the registry itself
      # rather than by naming any one prefix.
      Llm::UntrustedTextBlock::PREFIXES.each_value do |prefix|
        text = "<#{prefix}-#{SecureRandom.hex(8)}>"
        expect(described_class.normalize_delimiters(text)).to eq("<#{prefix}-<16-hex>>")
      end
    end
  end

  describe "BillPositionsPromptBuilder byte stability (the property the hashing relies on)" do
    it "produces identical system_prompt strings across two instances over the same bill" do
      first = BillPositionsPromptBuilder.new(bill)
      second = BillPositionsPromptBuilder.new(bill)

      expect(first.system_prompt).to eq(second.system_prompt)
    end

    it "produces different user_message strings, but identical normalized user_message strings" do
      first = BillPositionsPromptBuilder.new(bill)
      second = BillPositionsPromptBuilder.new(bill)

      expect(first.user_message).not_to eq(second.user_message)
      expect(described_class.normalize_delimiters(first.user_message))
        .to eq(described_class.normalize_delimiters(second.user_message))
    end
  end

  describe ".call" do
    it "returns a manifest entry Hash carrying every required field" do
      entry = described_class.call(bill: bill, answer_type: "positions")

      expect(entry).to include(
        "external_id" => bill.external_id,
        "answer_type" => "positions",
        "builder_class" => "BillPositionsPromptBuilder",
        "user_message_hash_is_delimiter_normalised" => true
      )
      %w[system_prompt_sha256 system_prompt_bytes user_message_sha256 user_message_bytes
        builder_content_digest builder_digest_files dumped_at].each do |key|
        expect(entry[key]).not_to be_nil, "manifest entry missing #{key}"
      end
    end

    it "hashes the system prompt directly and the user message only after normalization" do
      builder = BillPositionsPromptBuilder.new(bill)
      entry = described_class.call(bill: bill, answer_type: "positions")

      expect(entry["system_prompt_sha256"]).to eq(Digest::SHA256.hexdigest(builder.system_prompt))
      expect(entry["user_message_sha256"])
        .to eq(Digest::SHA256.hexdigest(described_class.normalize_delimiters(builder.user_message)))
    end

    it "writes exactly the two payload files under Legislation::Paths.prompt_dumps and nothing else" do
      described_class.call(bill: bill, answer_type: "positions")

      dir = Legislation::Paths.prompt_dump_file(bill.external_id, answer_type: "positions", sway_locale: sway_locale.name)
      written = Dir.glob(dir.join("*")).sort

      expect(written).to eq(
        [dir.join("positions.system.txt").to_s, dir.join("positions.user.txt").to_s].sort
      )
    end

    it "produces two dumps of the same bill whose system and user hashes agree" do
      first_entry = described_class.call(bill: bill, answer_type: "positions")
      second_entry = described_class.call(bill: bill, answer_type: "positions")

      expect(first_entry["system_prompt_sha256"]).to eq(second_entry["system_prompt_sha256"])
      expect(first_entry["user_message_sha256"]).to eq(second_entry["user_message_sha256"])
    end

    it "raises rather than producing a path when the external id fails EXTERNAL_ID_PATTERN" do
      bill.update_column(:external_id, "../../etc/passwd")

      expect { described_class.call(bill: bill.reload, answer_type: "positions") }
        .to raise_error(Legislation::Paths::UnsafeExternalIdError)
    end
  end

  describe ".builder_content_digest" do
    it "is a SHA-256 over each watched file's repo-relative path mixed with its bytes, in list order" do
      manual = Digest::SHA256.new
      described_class::WATCHED_BUILDER_FILES.each do |relative_path|
        manual << relative_path
        manual << Rails.root.join(relative_path).binread
      end

      expect(described_class.builder_content_digest).to eq(manual.hexdigest)
    end

    it "moves when an uncommitted edit changes a watched file's contents" do
      original_digest = described_class.builder_content_digest
      watched_path = Rails.root.join(described_class::WATCHED_BUILDER_FILES.last)
      original_bytes = watched_path.binread

      begin
        watched_path.binwrite("#{original_bytes}\n# spec-injected uncommitted edit, restored in the ensure block\n")
        expect(described_class.builder_content_digest).not_to eq(original_digest)
      ensure
        watched_path.binwrite(original_bytes)
      end
    end

    it "computes with no git binary on PATH" do
      original_path = ENV.fetch("PATH", nil)

      begin
        ENV["PATH"] = ""
        expect { described_class.builder_content_digest }.not_to raise_error
      ensure
        ENV["PATH"] = original_path
      end
    end
  end

  describe "the summary answer type" do
    let(:diff_markdown_path) do
      Legislation::Paths.diff_markdown_file(bill.external_id, sway_locale: sway_locale.name)
    end

    def write_diff_markdown(body = "## Section 1\n\nStrike the words \"annual\" and insert \"quarterly\".\n")
      diff_markdown_path.dirname.mkpath
      diff_markdown_path.write(body)
    end

    def persist_non_amending_sentinel
      bill.update!(extracted_text: "An act establishing a civic engagement advisory council.")
      parsed = ParseSectionsService.new(bill: bill).call
      expect(parsed.amendment_source).to eq("none")
      expect(parsed.section_reference_ids).to be_empty
      expect(parsed.operation_ids).to be_empty
      generated = GenerateDiffsService.new(bill: bill).call
      expect(generated.diff_markdown_path).to be_nil
      bill.reload
      sentinel = JSON.parse(bill.bill_llm_provisioning.diff_content)
      expect(sentinel["extracted_text_sha256"])
        .to eq(Digest::SHA256.hexdigest(bill.extracted_text))
      nil
    end

    before do
      create(:category, name: "Housing")
      create(:category, name: "Public Safety")
      create(:category, name: "Retired Topic", active: false)
    end

    it "builds from BillSummaryPromptBuilder with the active categories the production job queries" do
      write_diff_markdown
      expected = BillSummaryPromptBuilder.new(bill, active_categories: Category.where(active: true).order(:name).to_a)

      entry = described_class.call(bill: bill, answer_type: "summary")

      expect(entry["builder_class"]).to eq("BillSummaryPromptBuilder")
      expect(entry["answer_type"]).to eq("summary")
      expect(entry["system_prompt_sha256"]).to eq(Digest::SHA256.hexdigest(expected.system_prompt))
    end

    it "uses extracted text only for a fresh persisted non-amending sentinel" do
      persist_non_amending_sentinel
      expected = BillSummaryPromptBuilder.new(bill, active_categories: Category.where(active: true).order(:name).to_a)

      entry = described_class.call(bill: bill, answer_type: "summary")

      expect(entry["builder_class"]).to eq("BillSummaryPromptBuilder")
      expect(entry["source_section_heading"]).to eq("## Bill text (extracted)")
      expect(entry["user_message_sha256"])
        .to eq(Digest::SHA256.hexdigest(described_class.normalize_delimiters(expected.user_message)))
    end

    it "rejects a sentinel when extracted text changes after diff generation" do
      persist_non_amending_sentinel
      bill.update!(extracted_text: "Changed text after the diff sentinel was generated.")

      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError)
    end

    it "keeps a valid sentinel current after a summary-only save" do
      persist_non_amending_sentinel
      bill.update_columns(summary: "A previously generated summary", updated_at: Time.current)

      expect { described_class.call(bill: bill, answer_type: "summary") }.not_to raise_error
    end

    it "rejects a sentinel whose file id does not match the bill" do
      persist_non_amending_sentinel
      payload = JSON.parse(bill.bill_llm_provisioning.diff_content)
      payload["file_id"] = "HB0001"
      bill.bill_llm_provisioning.update!(diff_content: payload.to_json)

      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError)
    end

    it "rejects nonzero sentinel stats and malformed sentinel JSON" do
      persist_non_amending_sentinel
      provisioning = bill.bill_llm_provisioning
      payload = JSON.parse(provisioning.diff_content)
      payload["stats"]["total_operations"] = 1
      provisioning.update!(diff_content: payload.to_json)

      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError)

      payload["stats"]["total_operations"] = 0.0
      provisioning.update!(diff_content: payload.to_json)
      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError)

      provisioning.update!(diff_content: "{")
      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError)
    end

    it "rejects an amendment bill and a sentinel older than parsing" do
      persist_non_amending_sentinel
      bill.update_column(:amendment_source, "text_pattern")

      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError)

      bill.update_column(:amendment_source, "none")
      bill.bill_llm_provisioning.update!(diff_generated_at: bill.parsed_at - 1.second)
      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError)
    end

    it "rejects a fresh section reference even when the caller's association was preloaded" do
      persist_non_amending_sentinel
      bill.bill_section_references.load
      create(:bill_section_reference, bill: bill)

      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError)
    end

    it "rejects an operation without a section reference" do
      persist_non_amending_sentinel
      create(:bill_amendment_operation, bill: bill, bill_section_reference: nil)

      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError)
    end

    it "rejects a non-amending sentinel without parsed bill provenance" do
      persist_non_amending_sentinel
      bill.update_column(:parsed_at, nil)

      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError)
    end

    it "raises MissingSourceError when a valid sentinel has no usable extracted text" do
      persist_non_amending_sentinel
      bill.update!(extracted_text: "   ")
      GenerateDiffsService.new(bill: bill).call

      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingSourceError)
    end

    it "writes the two summary payload files and nothing else" do
      write_diff_markdown

      described_class.call(bill: bill, answer_type: "summary")

      dir = Legislation::Paths.prompt_dump_file(bill.external_id, answer_type: "summary", sway_locale: sway_locale.name)
      expect(Dir.glob(dir.join("*")).sort)
        .to eq([dir.join("summary.system.txt").to_s, dir.join("summary.user.txt").to_s].sort)
    end

    it "raises MissingDiffMarkdownError naming the external id and the root setting, and writes nothing" do
      expect(diff_markdown_path).not_to exist

      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingDiffMarkdownError) { |error|
          expect(error.message).to include(bill.external_id)
          expect(error.message).to include("LEGISLATION_DIFFS_ROOT")
        }

      dir = Legislation::Paths.prompt_dump_file(bill.external_id, answer_type: "summary", sway_locale: sway_locale.name)
      expect(Dir.glob(dir.join("*"))).to be_empty
    end

    it "raises MissingSourceError naming the external id when the builder reports no source" do
      write_diff_markdown("   \n")
      bill.update!(extracted_text: nil)

      expect { described_class.call(bill: bill, answer_type: "summary") }
        .to raise_error(described_class::MissingSourceError, /#{Regexp.escape(bill.external_id)}/)

      dir = Legislation::Paths.prompt_dump_file(bill.external_id, answer_type: "summary", sway_locale: sway_locale.name)
      expect(Dir.glob(dir.join("*"))).to be_empty
    end

    it "records the source section heading the builder actually emitted" do
      write_diff_markdown

      entry = described_class.call(bill: bill, answer_type: "summary")

      expect(entry["source_section_heading"]).to eq("## Bill diff (bill vs. existing law)")
    end

    it "emits a source section heading that matches SOURCE_HEADING_PREFIXES['summary']" do
      write_diff_markdown

      entry = described_class.call(bill: bill, answer_type: "summary")
      heading = entry["source_section_heading"]
      prefixes = described_class::SOURCE_HEADING_PREFIXES.fetch("summary")

      expect(heading).to eq("## Bill diff (bill vs. existing law)")
      expect(prefixes).to include("## Bill diff")
      expect(prefixes.any? { |p| heading.start_with?(p) }).to be(true)
    end

    it "records the four effective caps and the ordered active category names beside their digest" do
      write_diff_markdown

      entry = described_class.call(bill: bill, answer_type: "summary")

      expect(entry["effective_caps"]).to eq(
        "llm_max_source_chars" => 300_000,
        "llm_max_testimony_tokens" => 90_000,
        "llm_max_testimony_chars" => 150_000,
        "llm_max_summary_context_chars" => 4_000
      )
      expect(entry["active_category_names_ordered"]).to eq(["Housing", "Public Safety"])
      expect(entry["active_category_digest"])
        .to eq(described_class.active_category_digest(["Housing", "Public Safety"]))
    end

    it "produces two summary dumps whose system and user hashes agree after normalization" do
      write_diff_markdown

      first_entry = described_class.call(bill: bill, answer_type: "summary")
      second_entry = described_class.call(bill: bill, answer_type: "summary")

      expect(first_entry["system_prompt_sha256"]).to eq(second_entry["system_prompt_sha256"])
      expect(first_entry["user_message_sha256"]).to eq(second_entry["user_message_sha256"])
    end

    it "normalizes all three of this builder's delimiter prefixes" do
      write_diff_markdown
      create(:bill_section_reference, bill: bill, key: "14-301", title: "Annual inspection requirement")
      active = Category.where(active: true).order(:name).to_a

      first = BillSummaryPromptBuilder.new(bill, active_categories: active).user_message
      second = BillSummaryPromptBuilder.new(bill, active_categories: active).user_message

      expect(first).not_to eq(second)
      expect(described_class.normalize_delimiters(first)).to eq(described_class.normalize_delimiters(second))
      [BillSummaryPromptBuilder::SOURCE_DELIMITER_PREFIX,
        BillSummaryPromptBuilder::METADATA_DELIMITER_PREFIX,
        BillSummaryPromptBuilder::CITATION_DELIMITER_PREFIX].each do |prefix|
        expect(described_class.normalize_delimiters(first)).to include("#{prefix}-<16-hex>")
      end
    end
  end

  describe ".active_category_digest" do
    it "changes when the same set of names is reordered" do
      expect(described_class.active_category_digest(["Housing", "Public Safety"]))
        .not_to eq(described_class.active_category_digest(["Public Safety", "Housing"]))
    end

    it "agrees for two calls over the same ordered names" do
      expect(described_class.active_category_digest(["Housing", "Public Safety"]))
        .to eq(described_class.active_category_digest(["Housing", "Public Safety"]))
    end
  end

  describe ".effective_caps" do
    it "reports the values the builders themselves resolve, not the raw settings" do
      expect(described_class.effective_caps).to eq(
        "llm_max_source_chars" => BillSummaryPromptBuilder.max_source_chars,
        "llm_max_testimony_tokens" => BillPositionsPromptBuilder.max_testimony_tokens,
        "llm_max_testimony_chars" => BillPositionsPromptBuilder.max_testimony_chars,
        "llm_max_summary_context_chars" => BillPositionsPromptBuilder.max_summary_context_chars
      )
    end
  end

  describe "the development-caps refusal" do
    it "raises naming all four settings and the dropped-environment-prefix trap" do
      with_app_config(
        :llm,
        llm_max_source_chars: 45_000,
        llm_max_testimony_tokens: 30_000,
        llm_max_testimony_chars: 45_000,
        llm_max_summary_context_chars: 4_000
      ) do
        expect { described_class.call(bill: bill, answer_type: "positions") }
          .to raise_error(described_class::DevelopmentCapsError) { |error|
            %w[LLM_MAX_SOURCE_CHARS LLM_MAX_TESTIMONY_TOKENS LLM_MAX_TESTIMONY_CHARS
              LLM_MAX_SUMMARY_CONTEXT_CHARS].each do |setting|
              expect(error.message).to include(setting)
            end
            expect(error.message).to match(/prefix .*dropped|DROPPED/i)
          }
      end
    end

    it "does not raise under the non-development caps the test environment resolves" do
      expect { described_class.call(bill: bill, answer_type: "positions") }.not_to raise_error
    end
  end
end
