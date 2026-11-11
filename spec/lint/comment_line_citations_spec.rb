# frozen_string_literal: true

require "rails_helper"

# @lat: [[comment-line-citation-rule#The rule: cite symbols, not lines]]
# Rule: comments cite symbols, not line numbers, in files this repo owns. Third-party
# citations (pinned by the lockfile) are exempt.
RSpec.describe "comments that cite a line number" do
  it "cites no line number in a file this repo owns" do
    # `foo.rb:123` or `foo/bar.tsx:45`.
    cited_line = %r{(?<path>[a-z0-9_/]+\.(?:rb|tsx?|ts)):(?<line>\d+)}

    sources = %w[app lib spec]
      .flat_map { |root| Dir.glob("#{root}/**/*.{rb,ts,tsx}") }
    ours = sources.to_set { |path| File.basename(path) }

    offenders = sources.flat_map do |path|
      File.read(path).each_line.with_index(1).filter_map do |line, number|
        next unless line.lstrip.start_with?("#", "//", "*")

        match = line.match(cited_line)
        next if match.nil?
        next unless ours.include?(File.basename(match[:path].to_s))

        "#{path}:#{number} cites #{match[0]} — name a method or constant instead"
      end
    end

    expect(offenders).to eq([])
  end
end
