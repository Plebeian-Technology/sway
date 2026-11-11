# frozen_string_literal: true

require "diff/lcs"

# @lat: [[generate-diffs-service-design#MarkdownRenderer: the Python-parity contract]]
class GenerateDiffsService
  module DiffRenderer
    module_function

    def make_diff_block(before_text, after_text)
      before_lines = before_text.lines
      after_lines = after_text.lines
      return "" if before_lines == after_lines

      # @type var out: Array[String]
      out = []
      Diff::LCS.sdiff(before_lines, after_lines).each do |change|
        case change.action
        when "=" then out << " #{change.old_element}"
        when "-" then out << "-#{change.old_element}"
        when "+" then out << "+#{change.new_element}"
        when "!"
          out << "-#{change.old_element}"
          out << "+#{change.new_element}"
        end
      end

      # @lat: [[generate-diffs-service-design#DiffRenderer: why an all-context diff renders as no diff at all]]
      return "" if out.all? { |line| line.start_with?(" ") }

      "```diff\n#{out.join("\n")}\n```"
    end
  end
end
