# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# This spec reads nothing but the committed manifest and the watched files'
# bytes: no corpus, no diff markdown, no API key, no network and no git.
RSpec.describe Eval::ManifestStaleness do
  around do |example|
    Dir.mktmpdir do |dir|
      @manifest_dir = Pathname.new(dir)
      example.run
    end
  end

  def write_manifest(entries)
    path = @manifest_dir.join("manifest.json")
    path.write(JSON.pretty_generate(entries))
    path
  end

  def fresh_entry(overrides = {})
    {
      "external_id" => "25-0064",
      "answer_type" => "positions",
      "builder_content_digest" => Eval::PromptDump.builder_content_digest,
      "builder_digest_files" => Eval::PromptDump::WATCHED_BUILDER_FILES,
      "builder_file_digests" => Eval::PromptDump.builder_file_digests
    }.merge(overrides)
  end

  def with_replaced_contents(relative_path)
    path = Rails.root.join(relative_path)
    original = path.binread
    begin
      path.binwrite("#{original}\n# spec-injected uncommitted edit, restored in the ensure block\n")
      yield
    ensure
      path.binwrite(original)
    end
  end

  describe "WATCHED_FILES" do
    it "is the very object Eval::PromptDump declares, not a second list that could drift" do
      expect(described_class::WATCHED_FILES).to equal(Eval::PromptDump::WATCHED_BUILDER_FILES)
    end

    it "names both prompt builders, the untrusted-text block, the prompt payload and the LLM settings" do
      expect(described_class::WATCHED_FILES).to include(
        "app/services/bill_positions_prompt_builder.rb",
        "app/services/bill_summary_prompt_builder.rb",
        "app/services/llm/untrusted_text_block.rb",
        "app/services/llm/prompt_payload.rb",
        "lib/sway/settings/llm.rb"
      )
    end
  end

  describe ".call" do
    it "passes when the recorded digest matches the watched files' current contents" do
      path = write_manifest("25-0064/positions" => fresh_entry)

      result = described_class.call(manifest_path: path)

      expect(result.checked_entries).to eq(1)
      expect(result.builder_content_digest).to eq(Eval::PromptDump.builder_content_digest)
    end

    it "raises when the recorded digest differs, naming the moved files and the fix" do
      stale = fresh_entry(
        "builder_content_digest" => "0" * 64,
        "builder_file_digests" => Eval::PromptDump.builder_file_digests
          .merge("lib/sway/settings/llm.rb" => "0" * 64)
      )
      path = write_manifest("25-0064/positions" => stale)

      expect { described_class.call(manifest_path: path) }
        .to raise_error(described_class::StaleManifestError) { |error|
          expect(error.message).to include("lib/sway/settings/llm.rb")
          expect(error.message).to include("sway:eval:dump")
          expect(error.message).not_to match(/edit the manifest/i)
        }
    end

    # The load-bearing case: a commit sha leaves a dirty working tree green
    # while the manifest already describes bytes the builders no longer emit.
    it "raises for an edit to a watched file that was never committed" do
      path = write_manifest("25-0064/positions" => fresh_entry)

      with_replaced_contents("app/services/bill_summary_prompt_builder.rb") do
        expect { described_class.call(manifest_path: path) }
          .to raise_error(described_class::StaleManifestError, %r{app/services/bill_summary_prompt_builder\.rb})
      end
    end

    it "still passes when a file the list does not name changes" do
      path = write_manifest("25-0064/positions" => fresh_entry)

      with_replaced_contents("lib/tasks/eval.rake") do
        expect { described_class.call(manifest_path: path) }.not_to raise_error
      end
    end

    it "computes its answer with no git binary on PATH" do
      path = write_manifest("25-0064/positions" => fresh_entry)
      original_path = ENV.fetch("PATH", nil)

      begin
        ENV["PATH"] = ""
        expect { described_class.call(manifest_path: path) }.not_to raise_error
      ensure
        ENV["PATH"] = original_path
      end
    end

    it "refuses a manifest recorded against a shorter watch list rather than comparing" do
      short = fresh_entry("builder_digest_files" => Eval::PromptDump::WATCHED_BUILDER_FILES.first(2))
      path = write_manifest("25-0064/positions" => short)

      expect { described_class.call(manifest_path: path) }
        .to raise_error(described_class::StaleManifestError, /watch list/i)
    end

    it "refuses a manifest with no entries, which would pass while checking nothing" do
      path = write_manifest({})

      expect { described_class.call(manifest_path: path) }
        .to raise_error(described_class::StaleManifestError, /no entries/i)
    end

    it "refuses a manifest path that does not exist" do
      expect { described_class.call(manifest_path: @manifest_dir.join("absent.json")) }
        .to raise_error(described_class::StaleManifestError, /sway:eval:dump/)
    end
  end

  describe "the committed eval/manifest.json" do
    it "describes the bytes the builders emit today" do
      expect { described_class.call(manifest_path: Rails.root.join("eval", "manifest.json")) }
        .not_to raise_error
    end
  end
end
