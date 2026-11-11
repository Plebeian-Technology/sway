# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"

# @lat: [[rubocop-cache-root-tcc-lock#Why the spec resolves the value the way rubocop does, not by matching text]]
RSpec.describe "the rubocop cache root" do
  def cache_root_from(working_directory)
    raw = Rails.root.join(".rubocop.yml").read
    Dir.chdir(working_directory) do
      YAML.safe_load(ERB.new(raw).result, aliases: true, permitted_classes: [Regexp, Symbol])
    end.dig("AllCops", "CacheRootDirectory")
  end

  it "is set at all, so no caller falls back to the protected root under $HOME" do
    expect(cache_root_from(Rails.root)).to be_present,
      "AllCops::CacheRootDirectory is unset, so rubocop uses $HOME/.cache — on a machine where that path is " \
      "protected every rubocop run dies in cleanup having inspected nothing, and the failure reaches the " \
      "regression gate, the pre-commit hook and any editor alike"
  end

  it "is absolute, so it cannot follow whoever invoked rubocop" do
    expect(cache_root_from(Rails.root)).to start_with("/"),
      "the cache root is relative, so it resolves against the caller's working directory and leaves a cache " \
      "directory wherever rubocop happened to be run from"
  end

  it "resolves to the same place from a subdirectory as from the repo root" do
    from_root = cache_root_from(Rails.root)
    from_subdirectory = cache_root_from(Rails.root.join("app"))

    expect(from_subdirectory).to eq(from_root),
      "running rubocop from a subdirectory resolves a different cache root, which is how app/tmp/rubocop_cache " \
      "appears: the main config load changes directory to this file first and the server's own lookup does not, " \
      "so a value that reads the working directory gives two answers"
  end

  it "points inside the repository, at a path git ignores" do
    expect(cache_root_from(Rails.root)).to eq(Rails.root.join("tmp").to_s),
      "the cache root is somewhere other than the repo's own tmp/, which is the one location that is both " \
      "writable without asking the operating system for anything and already ignored by git"
  end
end
