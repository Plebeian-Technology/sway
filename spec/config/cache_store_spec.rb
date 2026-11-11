# frozen_string_literal: true

require "rails_helper"

# The environment files are read as source rather than loaded: a spec run boots
# the test environment only, so nothing else here can see what development and
# production configure.
RSpec.describe "config.cache_store per environment" do
  def cache_store_line(env)
    line = Rails.root.join("config", "environments", "#{env}.rb").read[/^\s*config\.cache_store\s*=.*$/]
    line or raise "no config.cache_store line found in config/environments/#{env}.rb"
  end

  # @lat: [[auxiliary-databases#Why development's cache has to be a real store]]
  it "gives development a store that survives a reload" do
    expect(cache_store_line("development")).to include(":solid_cache_store")
  end

  # @lat: [[auxiliary-databases#The Solid Cache database replaces two different broken caches]]
  it "gives production a store that survives a deploy" do
    line = cache_store_line("production")

    expect(line).to include(":solid_cache_store")
    expect(line).not_to include("file_store"),
      "a file store under tmp/ is discarded on every deploy and is private to " \
      "each container, so a value one container wrote is invisible to the other."
  end

  # @lat: [[auxiliary-databases#Why test keeps cable on the primary database and gives cache none at all]]
  it "leaves test on a store that keeps nothing" do
    expect(cache_store_line("test")).to include(":null_store")
  end

  # @lat: [[auxiliary-databases#The Solid Cache database replaces two different broken caches]]
  it "gives development and production the same mechanism" do
    expect(cache_store_line("development").strip).to eq(cache_store_line("production").strip)
  end
end
