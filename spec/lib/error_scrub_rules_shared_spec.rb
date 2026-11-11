# frozen_string_literal: true

require "rails_helper"

# @lat: [[sway-error-scrubber-design#Why the rules table has three readers]]
RSpec.describe "the shared error-scrub table" do
  let(:table_path) { Rails.root.join("app", "frontend", "sway_constants", "errorScrubRules.json") }
  let(:table) { JSON.parse(table_path.read) }

  let(:readers) do
    {
      "Ruby" => "lib/sway_error_scrubber.rb",
      "web" => "app/frontend/sway_utils/scrub_error_event.ts",
      "mobile" => "mobile/src/observability/scrub_error_event.ts"
    }
  end

  it "holds every rule the scrubbers need" do
    expect(table.keys).to include("redactions", "droppedKeys", "preservedKeys", "maxStringLength", "maxDepth")
    expect(table.fetch("redactions")).to all(include("label", "pattern"))
  end

  # The whole filename, not a prefix. A substring match passed a mutation that
  # pointed one reader at errorScrubRulesXX.json — measured 2026-08-12.
  it "is read by all three scrubbers" do
    silent = readers.reject { |_name, path| Rails.root.join(path).read.include?(table_path.basename.to_s) }

    expect(silent).to be_empty,
      "these no longer read the shared table, so they can drift again: #{silent.keys.join(", ")}"
  end

  # @lat: [[sway-error-scrubber-design#Why one spec detects a pasted list, not just a missing table reference]]
  it "leaves no scrubber holding its own copy of the lists" do
    values = table.fetch("droppedKeys") + table.fetch("preservedKeys")

    own_copies = readers.filter_map do |name, path|
      pasted = Rails.root.join(path).read.lines.find do |line|
        values.count { |value| line.include?(%("#{value}")) } >= 3
      end
      "#{name}: #{pasted.strip}" if pasted
    end

    expect(own_copies).to be_empty,
      "these spell out a list that belongs in the table, so a change to one would " \
      "leave the others behind: #{own_copies.join("; ")}"
  end

  # Ruby compiles the pattern source with Regexp.new and JavaScript with
  # RegExp. A pattern only one of them can read would scrub on one platform.
  it "carries patterns Ruby can compile" do
    expect { table.fetch("redactions").each { |rule| Regexp.new(rule.fetch("pattern")) } }.not_to raise_error
  end
end
