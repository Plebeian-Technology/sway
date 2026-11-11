# frozen_string_literal: true

# @lat: [[generate-diffs-service-design#MarkdownRenderer: the Python-parity contract]]
class GenerateDiffsService
  class MarkdownRenderer
    def initialize(bill, diff_result)
      @bill = bill
      @diff_result = diff_result
    end

    def render
      title = @diff_result["title"].to_s
      target = @diff_result["target"].to_s
      stats = @diff_result["stats"]
      generated_date = @diff_result["generated_at"].to_s[0, 10]

      # @lat: [[rbs-signatures#Why a mixed-value document Hash needs a per-key guard]]
      sections_modified = stats.is_a?(Hash) ? stats["sections_modified"] : nil
      sections_not_found = stats.is_a?(Hash) ? stats["sections_not_found"] : nil

      # @type var md_parts: Array[String]
      md_parts = []
      md_parts << "# #{title}\n"
      md_parts << "- **Target:** #{target}"
      md_parts << "- **Sections modified:** #{sections_modified}"
      md_parts << "- **Sections not found:** #{sections_not_found}"
      md_parts << "- **Generated:** #{generated_date}\n"
      md_parts << "---\n"
      md_parts.concat(content_parts)

      md_parts.join("\n")
    end

    private

    # @lat: [[generate-diffs-service-design#MarkdownRenderer: why sections are grouped by article]]
    def content_parts
      # @type var groups: Hash[String, Array[GenerateDiffsService::diff_section_augmented]]
      groups = {}
      # @lat: [[rbs-signatures#Why a mixed-value document Hash needs a per-key guard]]
      sections = @diff_result["sections"]
      # @type var raw_sections: Array[GenerateDiffsService::diff_section_augmented]
      raw_sections = sections.is_a?(::Array) ? sections : []
      raw_sections.each do |sec|
        article =
          if sec["status"] == "section_not_found"
            "Unresolved References"
          else
            sec["article"].to_s
          end
        groups[article] ||= []
        groups[article] << sec
      end

      # @type var parts: Array[String]
      parts = []
      groups.each do |article_name, sections|
        parts << "## #{article_name}\n"
        sections.each { |sec| parts.concat(render_section(sec)) }
      end
      parts
    end

    def render_section(sec)
      # @type var out: Array[String]
      out = []
      case sec["status"]
      when "section_not_found"
        out << "### #{sec["title"] || sec["key"]}\n"
        out << "> **Section not found:** This section was referenced in the bill" \
          " but could not be matched to a section in the law corpus.\n"
      when "referenced_only"
        out << "### Section #{sec["title"]}\n"
        out << "> Bill references this section but no specific amendments were detected.\n"
        out << "```\n#{sec["_before_text"]}\n```\n"
      when "operation_failed"
        out << "### Section #{sec["title"]}\n"
        out << "> **Warning:** Some operations could not be applied to this section.\n" \
          "> Showing original law text only.\n"
        out << "```\n#{sec["_before_text"]}\n```\n"
      when "modified", "markup_modified"
        heading = (sec["key"] == "unattributed_amendments") ? "### #{sec["title"]}\n" : "### Section #{sec["title"]}\n"
        out << heading
        out << "#{sec["_diff_block"]}\n"
      end
      out
    end
  end
end
