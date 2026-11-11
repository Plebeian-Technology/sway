# frozen_string_literal: true

# @lat: [[generate-diffs-service-design#ApplyOperations: the Python-parity contract]]
class GenerateDiffsService
  class ApplyOperations
    ApplyResult = Struct.new(:after_text, :warnings)

    def self.call(before_text, operations)
      after = before_text.dup
      # @type var warnings: Array[String]
      warnings = []

      operations.each do |op|
        case op.operation.to_sym
        when :strike
          anchor = op.anchor_text.to_s
          if after.include?(anchor)
            # @lat: [[generate-diffs-service-design#ApplyOperations: the Python-parity contract]]
            after = after.sub(anchor) { "" }
          else
            warnings << "STRIKE text not found: #{anchor[0, 60].inspect}"
          end

        when :insert
          # @lat: [[generate-diffs-service-design#ApplyOperations: the Python-parity contract]]
          payload = (op.replacement_text || op.anchor_text).to_s
          after = "#{after}\n#{payload}"

        when :replace
          # @lat: [[bill-amendment-operation-column-contract#How the two text columns are filled for a text-pattern match]]
          combined =
            if !op.anchor_text.to_s.empty? && !op.replacement_text.to_s.empty?
              "#{op.anchor_text} -> #{op.replacement_text}"
            else
              op.anchor_text.to_s
            end

          unless combined.include?(" -> ")
            warnings << "REPLACE missing ' -> ' separator: #{combined[0, 60].inspect}"
            next
          end

          old_text, new_text = combined.split(" -> ", 2)
          # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
          next if old_text.nil? || new_text.nil?

          if after.include?(old_text)
            # @lat: [[generate-diffs-service-design#ApplyOperations: the Python-parity contract]]
            after = after.sub(old_text) { new_text }
          else
            warnings << "REPLACE source not found: #{old_text[0, 60].inspect}"
          end
        end
      end

      ApplyResult.new(after_text: after, warnings: warnings)
    end
  end
end
