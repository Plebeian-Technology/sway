# frozen_string_literal: true

# @lat: [[generate-diffs-service-design#ResultWriter: why a disk failure becomes BillProcessingError, not a run-killing error]]
class GenerateDiffsService
  class ResultWriter
    def self.root
      Legislation::Paths.diffs
    end

    def self.write_json(bill, payload)
      path = Legislation::Paths.diff_json_file(bill.external_id, sway_locale: bill.sway_locale&.name)
      Legislation::ArtifactWriter.write(path, JSON.pretty_generate(payload), stage: "generate_diffs")
    end

    # @lat: [[generate-diffs-service-design#ResultWriter: why write_markdown checks the type of body before writing]]
    def self.write_markdown(bill, body)
      raise ArgumentError, "write_markdown: body must be a String (got #{body.class})" unless body.is_a?(::String)
      text = body #: String

      path = Legislation::Paths.diff_markdown_file(bill.external_id, sway_locale: bill.sway_locale&.name)
      Legislation::ArtifactWriter.write(path, text, stage: "generate_diffs")
    end
  end
end
