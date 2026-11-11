# frozen_string_literal: true

module Eval
  # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the payload is built through Llm::PromptPayload, not call]]
  class PromptDump
    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the summary dump refuses rather than falling back]]
    class MissingSourceError < StandardError; end

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the summary dump refuses rather than falling back]]
    class MissingDiffMarkdownError < StandardError; end

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the caps are asserted and recorded]]
    class DevelopmentCapsError < StandardError; end

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the staleness discriminator is a content digest, not a commit sha]]
    WATCHED_BUILDER_FILES = %w[
      app/services/bill_positions_prompt_builder.rb
      app/services/bill_summary_prompt_builder.rb
      app/services/llm/untrusted_text_block.rb
      app/services/llm/prompt_payload.rb
      lib/sway/settings/llm.rb
    ].freeze

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the caps are asserted and recorded]]
    NON_DEVELOPMENT_CAPS = {
      "llm_max_source_chars" => 300_000,
      "llm_max_testimony_tokens" => 90_000,
      "llm_max_testimony_chars" => 150_000,
      "llm_max_summary_context_chars" => 4_000
    }.freeze

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the source section heading is recorded]]
    SOURCE_HEADING_PREFIXES = {
      "positions" => ["## Testimony"].freeze,
      "summary" => ["## Bill diff", "## Bill text"].freeze
    }.freeze

    class << self
      def call(bill:, answer_type:)
        new(bill: bill, answer_type: answer_type).call
      end

      # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the user-message hash is delimiter-normalised]]
      def normalize_delimiters(text)
        Llm::UntrustedTextBlock::PREFIXES.each_value.reduce(text) do |acc, prefix|
          acc.gsub(/(#{Regexp.escape(prefix)})-[0-9a-f]{16}/, '\1-<16-hex>')
        end
      end

      # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the staleness discriminator is a content digest, not a commit sha]]
      def builder_content_digest
        digest = Digest::SHA256.new
        WATCHED_BUILDER_FILES.each do |relative_path|
          digest << relative_path
          digest << Rails.root.join(relative_path).binread
        end
        digest.hexdigest
      end

      # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the staleness discriminator is a content digest, not a commit sha]]
      def builder_file_digests
        WATCHED_BUILDER_FILES.to_h do |relative_path|
          [relative_path, Digest::SHA256.hexdigest(Rails.root.join(relative_path).binread)]
        end
      end

      # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the caps are asserted and recorded]]
      def effective_caps
        {
          "llm_max_source_chars" => BillSummaryPromptBuilder.max_source_chars,
          "llm_max_testimony_tokens" => BillPositionsPromptBuilder.max_testimony_tokens,
          "llm_max_testimony_chars" => BillPositionsPromptBuilder.max_testimony_chars,
          "llm_max_summary_context_chars" => BillPositionsPromptBuilder.max_summary_context_chars
        }
      end

      # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the category digest is taken over ordered names]]
      def active_category_names_ordered
        Category.where(active: true).order(:name).pluck(:name)
      end

      # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the category digest is taken over ordered names]]
      def active_category_digest(names = active_category_names_ordered)
        digest = Digest::SHA256.new
        names.each do |name|
          digest << name.to_s.bytesize.to_s
          digest << "\n"
          digest << name.to_s
        end
        digest.hexdigest
      end

      # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the caps are asserted and recorded]]
      def assert_non_development_caps!
        caps = effective_caps
        return if caps == NON_DEVELOPMENT_CAPS

        raise DevelopmentCapsError, <<~MESSAGE
          Eval::PromptDump refuses to dump under these truncation caps:
            llm_max_source_chars:          #{caps.fetch("llm_max_source_chars")} (want #{NON_DEVELOPMENT_CAPS.fetch("llm_max_source_chars")})
            llm_max_testimony_tokens:      #{caps.fetch("llm_max_testimony_tokens")} (want #{NON_DEVELOPMENT_CAPS.fetch("llm_max_testimony_tokens")})
            llm_max_testimony_chars:       #{caps.fetch("llm_max_testimony_chars")} (want #{NON_DEVELOPMENT_CAPS.fetch("llm_max_testimony_chars")})
            llm_max_summary_context_chars: #{caps.fetch("llm_max_summary_context_chars")} (want #{NON_DEVELOPMENT_CAPS.fetch("llm_max_summary_context_chars")})

          `dip run bundle exec rake` runs RAILS_ENV=development, where three of the four
          caps default smaller than everywhere else. An environment prefix placed in
          front of `dip run` is DROPPED -- dip forwards a host variable into the
          container only when dip.yml names it for that command. Pass all four as
          trailing NAME=VALUE arguments to the rake invocation itself; Rake reads those
          from its own argv:

            dip run bundle exec rake sway:eval:dump \\
              LLM_MAX_SOURCE_CHARS=300000 LLM_MAX_TESTIMONY_TOKENS=90000 \\
              LLM_MAX_TESTIMONY_CHARS=150000 LLM_MAX_SUMMARY_CONTEXT_CHARS=4000
        MESSAGE
      end
    end

    def initialize(bill:, answer_type:)
      @bill = bill
      @answer_type = answer_type
    end

    def call
      self.class.assert_non_development_caps!
      builder = build_builder
      payload = Llm::PromptPayload.new(system_prompt: builder.system_prompt, user_message: builder.user_message)
      write_files(payload)
      manifest_entry(builder, payload)
    end

    private

    attr_reader :bill, :answer_type

    def build_builder
      case answer_type
      when "positions"
        BillPositionsPromptBuilder.new(bill)
      when "summary"
        summary_builder
      else
        raise ArgumentError,
          "Eval::PromptDump has no builder registered for answer_type #{answer_type.inspect} " \
          "-- registered types are #{SOURCE_HEADING_PREFIXES.keys.inspect}"
      end
    end

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the summary dump refuses rather than falling back]]
    def summary_builder
      @bill = Bill.find(bill.id)
      require_diff_markdown_or_non_amending_sentinel!
      builder = BillSummaryPromptBuilder.new(bill, active_categories: active_categories)
      return builder if builder.source_present?

      raise MissingSourceError,
        "Eval::PromptDump: BillSummaryPromptBuilder reports no source text for bill " \
        "#{bill.external_id}. Production skips the summary call entirely in that case " \
        "(GenerateBillSummaryJob gates on #source_present?), so a dump here would record " \
        "a call that never happens."
    end

    def active_categories
      @active_categories ||= Category.where(active: true).order(:name).to_a
    end

    def active_category_names
      active_categories.map(&:name)
    end

    def diff_markdown_path
      Legislation::Paths.diff_markdown_file(bill.external_id, sway_locale: bill.sway_locale&.name)
    end

    def require_diff_markdown_or_non_amending_sentinel!
      return if diff_markdown_path.exist?
      return if verified_non_amending_sentinel?

      raise MissingDiffMarkdownError,
        "Eval::PromptDump: bill #{bill.external_id} has no diff markdown at " \
        "#{diff_markdown_path}. LEGISLATION_DIFFS_ROOT decides where those files live " \
        "(it falls back to LEGISLATION_ROOT/diffs). Generate the diff for this bill and " \
        "re-run; do not dump without it."
    end

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the summary dump refuses rather than falling back]]
    def verified_non_amending_sentinel?
      provisioning = BillLlmProvisioning.find_by(bill_id: bill.id)
      return false unless provisioning

      parsed_at = bill.parsed_at
      diff_generated_at = provisioning.diff_generated_at
      return false unless bill.amendment_source == "none" && parsed_at && diff_generated_at
      parsed_time = parsed_at.to_time
      diff_generated_time = diff_generated_at.to_time
      return false if BillSectionReference.where(bill_id: bill.id).exists?
      return false if BillAmendmentOperation.where(bill_id: bill.id).exists?

      payload = JSON.parse(provisioning.diff_content.to_s)
      payload.is_a?(Hash) &&
        payload.keys.sort == %w[extracted_text_sha256 file_id generated_at sections stats summary target title] &&
        payload["file_id"] == bill.external_id &&
        payload["extracted_text_sha256"] == Digest::SHA256.hexdigest(bill.extracted_text.to_s) &&
        payload["title"] == bill.title &&
        payload["target"] == bill.parsing_target &&
        payload["summary"].nil? &&
        payload["sections"] == [] &&
        zero_sentinel_stats?(payload["stats"]) &&
        payload["generated_at"].is_a?(String) &&
        Time.iso8601(payload.fetch("generated_at")) >= parsed_time &&
        Time.iso8601(payload.fetch("generated_at")) <= diff_generated_time
    rescue JSON::ParserError, KeyError, ArgumentError, TypeError
      false
    end

    def zero_sentinel_stats?(stats)
      expected_keys = %w[
        sections_modified sections_referenced_only sections_not_found total_operations
      ].sort
      stats.is_a?(Hash) &&
        stats.keys.sort == expected_keys &&
        stats.values.all? { |value| value.is_a?(Integer) && value.zero? }
    end

    def dump_dir
      @dump_dir ||= Legislation::Paths.prompt_dump_file(
        bill.external_id, answer_type: answer_type, sway_locale: bill.sway_locale.name
      )
    end

    def write_files(payload)
      FileUtils.mkdir_p(dump_dir)
      dump_dir.join("#{answer_type}.system.txt").write(payload.system_prompt)
      dump_dir.join("#{answer_type}.user.txt").write(payload.user_message)
    end

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the source section heading is recorded]]
    def source_section_heading(user_message)
      prefixes = SOURCE_HEADING_PREFIXES.fetch(answer_type, [])
      user_message.each_line.map(&:chomp).find { |line|
        prefixes.any? { |prefix| line.start_with?(prefix) }
      }
    end

    def manifest_entry(builder, payload)
      normalized_user_message = self.class.normalize_delimiters(payload.user_message)
      names = active_category_names

      {
        "external_id" => bill.external_id,
        "answer_type" => answer_type,
        "system_prompt_sha256" => Digest::SHA256.hexdigest(payload.system_prompt),
        "system_prompt_bytes" => payload.system_prompt.bytesize,
        "user_message_sha256" => Digest::SHA256.hexdigest(normalized_user_message),
        "user_message_bytes" => payload.user_message.bytesize,
        "user_message_hash_is_delimiter_normalised" => true,
        "source_section_heading" => source_section_heading(payload.user_message),
        "builder_class" => builder.class.name,
        "builder_content_digest" => self.class.builder_content_digest,
        "builder_digest_files" => WATCHED_BUILDER_FILES,
        "builder_file_digests" => self.class.builder_file_digests,
        "effective_caps" => self.class.effective_caps,
        "active_category_digest" => self.class.active_category_digest(names),
        "active_category_names_ordered" => names,
        "dumped_at" => Time.current.utc.iso8601
      }
    end
  end
end
