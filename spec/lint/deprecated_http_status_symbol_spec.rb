# frozen_string_literal: true

require "rails_helper"

# @lat: [[deprecated-http-422-symbol-rule#The comment exception]]
# Comments are exempt from this check; only live Ruby usage is linted.
RSpec.describe "the deprecated name for HTTP 422" do
  it "is used nowhere in this repo's Ruby" do
    # Joined from two halves so this file is not its own first offender. The
    # alternative — skipping this path by name — is a gate that switches itself
    # off the day somebody renames the file, silently and while still printing
    # a pass.
    deprecated = [":unprocessable", "entity"].join("_")
    sources = %w[app lib spec].flat_map { |root| Dir.glob("#{root}/**/*.rb") }

    offenders = sources.flat_map do |path|
      File.read(path).each_line.with_index(1).filter_map do |line, number|
        next if line.lstrip.start_with?("#")
        next unless line.include?(deprecated)

        "#{path}:#{number} — use :unprocessable_content, which is Rack's current name for 422"
      end
    end

    expect(offenders).to eq([])
  end
end
