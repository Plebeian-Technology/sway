# frozen_string_literal: true

require "rails_helper"

# @lat: [[env-helpers-with-env-consolidation#Why with_app_config joins with_env rather than replacing it]]
RSpec.describe EnvHelpers do
  let(:key) { "SWAY_ENV_HELPERS_PROBE" }

  after { ["SWAY_ENV_HELPERS_PROBE", "SWAY_ENV_HELPERS_PROBE_2"].each { |name| ENV.delete(name) } }

  it "sets a value for the block and puts back what was there" do
    ENV[key] = "before"

    with_env(key => "during") do
      expect(ENV.fetch(key, nil)).to eq("during")
    end

    expect(ENV.fetch(key, nil)).to eq("before")
  end

  it "treats nil as 'make sure this is unset'" do
    ENV[key] = "before"

    with_env(key => nil) do
      expect(ENV.key?(key)).to be(false)
    end

    expect(ENV.fetch(key, nil)).to eq("before")
  end

  it "leaves a variable that was unset unset afterwards" do
    ENV.delete(key)

    with_env(key => "during") { nil }

    expect(ENV.key?(key)).to be(false)
  end

  it "restores every variable when the block raises" do
    other = "SWAY_ENV_HELPERS_PROBE_2"
    ENV[key] = "before"
    ENV.delete(other)

    expect {
      with_env(key => "during", other => "also") { raise ArgumentError, "boom" }
    }.to raise_error(ArgumentError)

    expect(ENV.fetch(key, nil)).to eq("before")
    expect(ENV.key?(other)).to be(false)
  end

  it "hands back what the block returned" do
    expect(with_env(key => "during") { :returned }).to eq(:returned)
  end

  # with_app_config joins with_env rather than replacing it -- a spec
  # that varies a migrated setting swaps the whole group instance instead of
  # the environment variable behind it (the memoized reader never re-reads
  # ENV, so with_env alone would not move it).
  describe "#with_app_config" do
    it "changes the group's value for the block and restores the previous instance after" do
      previous = Sway::Settings.upstream

      with_app_config(:upstream, legistar_api_base_url: "https://swapped.test") do
        expect(Sway::Settings.upstream.legistar_api_base_url).to eq("https://swapped.test")
      end

      expect(Sway::Settings.upstream).to equal(previous)
    end

    it "restores the previous group instance when the block raises" do
      previous = Sway::Settings.upstream

      expect {
        with_app_config(:upstream, legistar_api_base_url: "https://swapped.test") do
          raise ArgumentError, "boom"
        end
      }.to raise_error(ArgumentError)

      expect(Sway::Settings.upstream).to equal(previous)
    end

    it "hands back what the block returned" do
      result = with_app_config(:upstream, legistar_api_base_url: "https://swapped.test") { :returned }

      expect(result).to eq(:returned)
    end
  end
end
