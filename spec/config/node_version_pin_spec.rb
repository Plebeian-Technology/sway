# frozen_string_literal: true

require "rails_helper"

# @lat: [[node-version-pin-drift#Why every workflow reads a pin file instead of writing the version inline]]
RSpec.describe "the Node version pins" do
  # @lat: [[toolchain-pins#Which file answers depends on the tool]]
  def pins
    {
      "mise.toml" => Rails.root.join("mise.toml").read[/^node\s*=\s*"([^"]+)"/, 1],
      ".node-version" => Rails.root.join(".node-version").read.strip.delete_prefix("v"),
      "mobile/.node-version" => Rails.root.join("mobile", ".node-version").read.strip.delete_prefix("v")
    }
  end

  it "name the same version in every file that names one" do
    expect(pins.values.uniq.length).to eq(1), "disagreeing Node pins: #{pins.inspect}"
  end

  it "pin an exact version rather than an alias that moves on its own" do
    exact = /\A\d+\.\d+\.\d+\z/

    pins.each do |file, version|
      expect(version).to match(exact), "#{file} names #{version.inspect}, which moves on its own"
    end
  end

  # A workflow that writes the version inline is invisible to the two examples
  # above, which is how the mobile lane sat on 22 unnoticed. Every workflow
  # reads a pin file instead, so there is nothing to keep in step by hand.
  it "are read from a file by every workflow, never written inline" do
    inline = Rails.root.glob(".github/workflows/*.yml").select do |workflow|
      workflow.read.match?(/^\s*node-version:/)
    end

    expect(inline.map { |path| path.basename.to_s }).to be_empty
  end
end
