# frozen_string_literal: true

# @lat: [[legislation-pipeline#Diff artifacts describe changes to existing law]]
class GenerateDiffsService
  Result = Struct.new(
    :diff_result_path,
    :diff_markdown_path,
    :sections_modified,
    :sections_not_found,
    :total_operations
  )

  def initialize(bill:, bill_run: nil, run: nil)
    @bill = bill
    @bill_run = bill_run
    @run = run
  end

  def call
    # @lat: [[legislation-pipeline#The legislation pipeline#Diff artifacts describe changes to existing law#Non-amending bills conclude successfully]]
    if @bill.bill_section_references.empty? && @bill.bill_amendment_operations.empty?
      persist_diff_artifact!(empty_sentinel_payload)
      return Result.new(
        diff_result_path: nil,
        diff_markdown_path: nil,
        sections_modified: 0,
        sections_not_found: 0,
        total_operations: 0
      )
    end

    section_payloads, stats = build_section_payloads

    diff_result_disk = {
      "file_id" => @bill.external_id,
      "title" => @bill.title,
      "target" => @bill.parsing_target,
      # @lat: [[legislation-pipeline#Diff artifacts describe changes to existing law]]
      "generated_at" => ::Time.current.utc.iso8601(6).sub(/Z\z/, "+00:00"),
      # @lat: [[legislation-pipeline#Diff artifacts describe changes to existing law]]
      "summary" => nil,
      "sections" => section_payloads.map { |sec| strip_helper_keys(sec) },
      "stats" => stats
    }

    json_path = ResultWriter.write_json(@bill, diff_result_disk)

    augmented_payload = diff_result_disk.merge("sections" => section_payloads)
    md_body = MarkdownRenderer.new(@bill, augmented_payload).render
    md_path = ResultWriter.write_markdown(@bill, md_body)

    # @lat: [[legislation-pipeline#The legislation pipeline#Diff artifacts describe changes to existing law#Diff storage follows file creation]]
    persist_diff_artifact!(diff_result_disk)

    Result.new(
      diff_result_path: json_path,
      diff_markdown_path: md_path,
      sections_modified: Integer(stats["sections_modified"]),
      sections_not_found: Integer(stats["sections_not_found"]),
      total_operations: Integer(stats["total_operations"])
    )
  rescue ::ActiveRecord::RecordNotFound => e
    raise BillProcessingError,
      "generate_diffs failed for bill ##{@bill.id}: #{e.message[0, 500]}"
  end

  private

  HELPER_KEYS = %w[_diff_block _warnings _before_text _resolution].freeze

  def strip_helper_keys(section_hash)
    section_hash.except(*HELPER_KEYS)
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Diff artifacts describe changes to existing law#Non-amending bills conclude successfully]]
  def empty_sentinel_payload
    {
      "file_id" => @bill.external_id,
      "title" => @bill.title,
      "target" => @bill.parsing_target,
      "generated_at" => ::Time.current.utc.iso8601(6).sub(/Z\z/, "+00:00"),
      "summary" => nil,
      "sections" => [],
      "extracted_text_sha256" => Digest::SHA256.hexdigest(@bill.extracted_text.to_s),
      "stats" => {
        "sections_modified" => 0,
        "sections_referenced_only" => 0,
        "sections_not_found" => 0,
        "total_operations" => 0
      }
    }
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Diff artifacts describe changes to existing law#Diff storage follows file creation]]
  def persist_diff_artifact!(payload)
    provisioning =
      @bill.bill_llm_provisioning || @bill.build_bill_llm_provisioning
    provisioning.diff_content = JSON.generate(payload)
    provisioning.diff_generated_at = ::Time.zone.now
    provisioning.save!
  end

  # @lat: [[legislation-pipeline#Law sections stay within their jurisdiction]]
  def lookup_law_section(ref, sway_locale)
    return nil if ref.resolution.to_s == "unresolved"
    return nil if sway_locale.nil?

    ::LawSection.by_sway_locale(sway_locale).find_by(key: ref.key)
  end

  def build_section_payloads
    # @type var sections: Array[Hash[String, untyped]]
    sections = []
    # @type var stats: Hash[String, Integer]
    stats = {
      "sections_modified" => 0,
      "sections_referenced_only" => 0,
      "sections_not_found" => 0,
      "total_operations" => 0
    }

    sway_locale = @bill.sway_locale

    # @lat: [[legislation-pipeline#The legislation pipeline#Diff artifacts describe changes to existing law#Amendment operations are grouped once]]
    all_ops = ::BillAmendmentOperation
      .where(bill_id: @bill.id)
      .where.not(bill_section_reference_id: nil)
      .order(:ordinal)
      .to_a
    ops_by_ref = all_ops.group_by(&:bill_section_reference_id)

    @bill.bill_section_references.order(:ordinal).each do |ref|
      law_section = lookup_law_section(ref, sway_locale)
      ops = ops_by_ref[ref.id] || []
      stats["total_operations"] += ops.size

      # @lat: [[legislation-pipeline#Typographic markup and declared target resolution]]
      markup_ops = ops.select { |o| o.source == "markup" }
      if markup_ops.any?
        section_text = extract_section_text(@bill.extracted_text.to_s, ref, markup_ops)
        before_text, after_text = ::Legislation::MarkupOps.reconstruct_before_and_after(section_text)
        diff_block = DiffRenderer.make_diff_block(before_text, after_text)

        title = law_section&.title.presence || law_section&.section.presence || ref.title.presence || ref.section.presence || ref.key
        article = law_section&.article || ref.article

        if diff_block.present?
          stats["sections_modified"] += 1
          sections << {
            "key" => ref.key,
            "article" => article,
            "title" => title,
            "status" => "markup_modified",
            "operations_applied" => markup_ops.size,
            "_diff_block" => diff_block,
            "_before_text" => before_text
          }
        else
          stats["sections_referenced_only"] += 1
          sections << {
            "key" => ref.key,
            "article" => article,
            "title" => title,
            "status" => "referenced_only",
            "operations_applied" => 0,
            "_before_text" => before_text
          }
        end
        next
      end

      if law_section.nil?
        stats["sections_not_found"] += 1
        sections << {
          "key" => ref.key,
          "article" => ref.article,
          "title" => ref.title || ref.section,
          "status" => "section_not_found",
          "operations_applied" => 0,
          "_resolution" => ref.resolution
        }
        next
      end

      before_text = law_section.body.to_s
      if ops.empty?
        stats["sections_referenced_only"] += 1
        sections << {
          "key" => ref.key,
          "article" => law_section.article,
          "title" => law_section.title || law_section.section,
          "status" => "referenced_only",
          "operations_applied" => 0,
          "_before_text" => before_text
        }
        next
      end

      applied = ApplyOperations.call(before_text, ops)
      diff_block = DiffRenderer.make_diff_block(before_text, applied.after_text)
      successful_ops = ops.size - applied.warnings.size

      if successful_ops.zero?
        sections << {
          "key" => ref.key,
          "article" => law_section.article,
          "title" => law_section.title || law_section.section,
          "status" => "operation_failed",
          "operations_applied" => 0,
          "_warnings" => applied.warnings,
          "_before_text" => before_text
        }
      else
        stats["sections_modified"] += 1
        sections << {
          "key" => ref.key,
          "article" => law_section.article,
          "title" => law_section.title || law_section.section,
          "status" => "modified",
          "operations_applied" => successful_ops,
          "_diff_block" => diff_block,
          "_warnings" => applied.warnings
        }
      end
    end

    unattributed_markup_ops = ::BillAmendmentOperation
      .where(bill_id: @bill.id, bill_section_reference_id: nil, source: :markup)
      .order(:ordinal)
      .to_a

    if unattributed_markup_ops.any?
      before_text, after_text = ::Legislation::MarkupOps.reconstruct_before_and_after(@bill.extracted_text.to_s)
      diff_block = DiffRenderer.make_diff_block(before_text, after_text)

      if diff_block.present?
        stats["sections_modified"] += 1
        sections << {
          "key" => "unattributed_amendments",
          "article" => "Unattributed Amendments",
          "title" => "Unattributed Amendments",
          "status" => "markup_modified",
          "operations_applied" => unattributed_markup_ops.size,
          "_diff_block" => diff_block,
          "_before_text" => before_text
        }
      end
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Diff artifacts describe changes to existing law#Amendment operations are grouped once]]
    bill_level_ops = @bill.bill_amendment_operations.where(bill_section_reference_id: nil).count
    stats["total_operations"] += Integer(bill_level_ops)

    [sections, stats]
  end

  def extract_section_text(bill_text, ref, ops)
    return "" if bill_text.blank?

    first_op_start = ops.map(&:char_start).compact.min || 0
    needle = ref.anchor.to_s
    ref_start = if needle.present? && bill_text.include?(needle)
      bill_text.rindex(needle, first_op_start) || bill_text.index(needle) || first_op_start
    else
      first_op_start
    end

    last_op_end = ops.map(&:char_end).compact.max || bill_text.length
    boundary_match = bill_text.index(/(?:§\s+[A-Z0-9-]+|SECTION\s+\d+)/i, last_op_end)
    ref_end = boundary_match || bill_text.length

    ref_end = [ref_end, last_op_end].max
    ref_start = [ref_start, 0].max
    ref_start = [ref_start, ref_end].min

    bill_text[ref_start...ref_end].to_s.strip
  end
end
