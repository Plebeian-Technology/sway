# frozen_string_literal: true

require "rails_helper"

# config/routes.rb must assign no constant at the top level. Ruby warns
# "already initialized constant" when a boot loads that file more than once,
# and zero warnings is the baseline here.
# @lat: [[routes-top-level-constant-warning-detection#Why this reads the file rather than watching a redraw]]
RSpec.describe "config/routes.rb" do
  it "assigns no constant at the top level" do
    # Column zero is what makes it top level: everything inside the draw block
    # is indented. `[^=~]` keeps `==` and `=~` out of it.
    assignment = /\A[A-Z][A-Za-z0-9_]*(::[A-Za-z0-9_]+)*\s*=[^=~]/

    offenders = Rails.root.join("config", "routes.rb").readlines.each_with_index.filter_map do |line, index|
      "line #{index + 1}: #{line.strip}" if line.match?(assignment)
    end

    expect(offenders).to be_empty
  end
end
