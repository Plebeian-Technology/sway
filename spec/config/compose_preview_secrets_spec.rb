# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe ".dockerdev/compose.yml preview service secrets" do
  it "does not define non-empty literal fallback defaults for SECRET_KEY_BASE or RAILS_MASTER_KEY" do
    path = Rails.root.join(".dockerdev", "compose.yml")
    services = YAML.safe_load_file(path, aliases: true).fetch("services")
    preview_env = services.fetch("preview").fetch("environment")

    expect(preview_env["SECRET_KEY_BASE"]).to eq("${SECRET_KEY_BASE:-}")
    expect(preview_env["RAILS_MASTER_KEY"]).to eq("${RAILS_MASTER_KEY:-}")
  end
end
