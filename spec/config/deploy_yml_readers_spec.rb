# frozen_string_literal: true

require "rails_helper"

# @lat: [[deploy-yml-erb-then-yaml-reading#Why it needs checking]]
RSpec.describe "readers of config/deploy.yml" do
  # Runs the real script rather than repeating its parsing here — a copy of the
  # logic would have passed happily while the script itself was broken.
  it "resolves the Litestream credential's destination to a real machine" do
    stdout, stderr, status = Sway::Subprocess.capture3(
      Rails.root.join("scripts", "provision-litestream-key.sh").to_s,
      "--print-target",
      timeout_seconds: 30
    )

    expect(status.exitstatus).to eq(0), "script failed: #{stderr}"
    # An account, a machine, and an absolute path. Deliberately not an IPv4
    # pattern: the machine is named in deploy/config/sway.env now, and may
    # legitimately be a name rather than an address.
    expect(stdout.strip).to match(%r{\A[\w.-]+@[\w.-]+:/\S+\z}),
      "Expected an address the credential can actually be sent to, got " \
      "#{stdout.strip.inspect}. A value still carrying <%= %> means the script " \
      "read config/deploy.yml as plain YAML instead of rendering it first."
    expect(stdout.strip).not_to include("<%"),
      "the value still carries an unrendered ERB tag: #{stdout.strip.inspect}"
  end

  # @lat: [[litestream-credential#Why the destination is read out of the deploy configuration]]
  it "sends the credential to whichever machine SWAY_HOST names" do
    # A machine nobody owns. The point is that the variable WINS over whatever
    # deploy/config/sway.env says, so the value here must be one no file could
    # supply. ".invalid" can never resolve, so a mistake cannot reach anything.
    override_host = "override-target.invalid"
    keyfile_path = SwayDeployConfig.fetch("SWAY_KEYFILE_PATH")

    stdout, stderr, status = Sway::Subprocess.capture3(
      "/usr/bin/env",
      "SWAY_HOST=#{override_host}",
      Rails.root.join("scripts", "provision-litestream-key.sh").to_s,
      "--print-target",
      timeout_seconds: 30
    )

    expect(status.exitstatus).to eq(0), "script failed: #{stderr}"
    expect(stdout.strip).to end_with("@#{override_host}:#{keyfile_path}")
  end

  # The examples above pin the ONE reader that exists today. This one notices a
  # second one being added, because the next person to read this file will copy
  # the shape that is already there — and the broken shape is the shorter one.
  it "has no reader anywhere that skips the ERB step" do
    readers = Dir.chdir(Rails.root) do
      Dir.glob("{scripts,lib,bin,app,config}/**/*").select do |path|
        next false unless File.file?(path)
        next false if path == "config/deploy.yml"

        body = File.read(path)
        body.include?("deploy.yml") && body.match?(/YAML\.(load|safe_load|parse)/)
      end
    end

    offenders = readers.reject { |path| Rails.root.join(path).read.include?("ERB") }

    expect(offenders).to eq([]), <<~MESSAGE
      These read config/deploy.yml as plain YAML:

      #{offenders.join("\n")}

      Read it the way Kamal does — ERB first, then YAML:

          YAML.load(ERB.new(File.read("config/deploy.yml")).result, aliases: true)

      Reading it raw returns the unrendered text of anything not in quotes, which
      means an address like "<%= sway_host %>" comes back looking like an answer.
    MESSAGE
  end
end
