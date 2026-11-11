# frozen_string_literal: true

require "rails_helper"

# @lat: [[sway-error-scrubber-design#Why the production image must not delete RULES_PATH]]
RSpec.describe "the files Ruby reads that the production image deletes" do
  let(:dockerfile) do
    Rails.root.join("docker", "dockerfiles", "production.alpine.dockerfile").read
  end

  # Ruby that ships in the image and can therefore be loaded there.
  let(:shipped_ruby) { Rails.root.glob("{lib,app,config}/**/*.rb") }

  # Every app/frontend path named by a string in that Ruby.
  let(:paths_ruby_reads) do
    shipped_ruby.flat_map { |file|
      file.read.scan(%r{["'](app/frontend/[\w./-]+)["']}).flatten
    }.uniq.sort
  end

  # What survives the delete: `find ... ! -name X` keeps X.
  let(:preserved_names) { dockerfile.scan(/^\s*find\s+\S+.*?!\s+-name\s+(\S+)/).flatten }

  it "still deletes the directory, so this spec has something to check" do
    expect(dockerfile).to match(/find\s+app\/frontend\s+-mindepth/),
      "the production image no longer prunes app/frontend — if that is deliberate, delete this spec; " \
      "leaving it passes without checking anything"
  end

  # Without this the check can go quiet: no references found reads exactly like
  # every reference is safe.
  it "finds the Ruby that reads from there" do
    expect(paths_ruby_reads).not_to be_empty,
      "no shipped Ruby names an app/frontend path, which is either a rename or a broken pattern here"
  end

  it "keeps every one of those files in the image" do
    unpreserved = paths_ruby_reads.reject { |path| preserved_names.include?(File.basename(path)) }

    expect(unpreserved).to be_empty,
      "the production image deletes app/frontend but Ruby reads #{unpreserved.join(", ")} from it. " \
      "Production loads lib/ while starting, so this raises Errno::ENOENT and the container never boots. " \
      "Either keep the file in the Dockerfile's find, or stop reading it at load time."
  end
end
