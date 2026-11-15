# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

# @lat: [[deploy-values-boot-check#Why a missing OpenStates key stops the deploy in a hook]]
RSpec.describe "the pre-deploy hook's OpenStates key check" do
  let(:hook) { Rails.root.join(".kamal", "hooks", "pre-deploy").to_s }

  def run_hook(open_states_api_key)
    Dir.mktmpdir("pre-deploy-bin", Rails.root.join("tmp").to_s) do |bin|
      docker = File.join(bin, "docker")
      File.write(docker, "#!/bin/sh\nexit 1\n")
      File.chmod(0o755, docker)

      env = {"PATH" => "#{bin}:#{ENV.fetch("PATH")}", "OPEN_STATES_API_KEY" => open_states_api_key}
      _stdout, stderr, status = Open3.capture3(env, "sh", hook, chdir: Rails.root.to_s)
      [stderr, status]
    end
  end

  it "fails and names the key when the deploy environment has none" do
    stderr, status = run_hook(nil)

    expect(status).not_to be_success
    expect(stderr).to include("OPEN_STATES_API_KEY")
  end

  it "fails and names the key when the value is blank" do
    stderr, status = run_hook("")

    expect(status).not_to be_success
    expect(stderr).to include("OPEN_STATES_API_KEY")
  end

  it "lets the deploy continue when the key is present" do
    stderr, status = run_hook("a-key")

    expect(status).to be_success, stderr
  end
end
