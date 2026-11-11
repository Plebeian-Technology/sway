# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Development dependencies security" do
  it "does not declare better_errors or binding_of_caller in Gemfile" do
    gemfile_content = File.read(File.expand_path("../../Gemfile", __dir__.to_s))

    expect(gemfile_content).not_to match(/^\s*gem\s+["']better_errors["']/)
    expect(gemfile_content).not_to match(/^\s*gem\s+["']binding_of_caller["']/)
  end

  it "does not lock better_errors or binding_of_caller in Gemfile.lock" do
    gemfile_lock_content = File.read(File.expand_path("../../Gemfile.lock", __dir__.to_s))

    expect(gemfile_lock_content).not_to match(/\bbetter_errors\b/)
    expect(gemfile_lock_content).not_to match(/\bbinding_of_caller\b/)
  end
end
