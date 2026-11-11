# frozen_string_literal: true

require "rails_helper"

# @lat: [[sqlite-integrity-check-boot-hook#Why the integrity check initializer is a thin hook]]
RSpec.describe "config/initializers/sqlite_integrity_check.rb" do
  it "runs SqliteIntegrityCheck in the web server process" do
    allow(Sway::BootEnqueue).to receive(:web_server_process?).and_return(true)
    expect(SqliteIntegrityCheck).to receive(:run).with(env: Rails.env)

    load Rails.root.join("config", "initializers", "sqlite_integrity_check.rb").to_s
  end

  it "skips SqliteIntegrityCheck outside the web server process" do
    allow(Sway::BootEnqueue).to receive(:web_server_process?).and_return(false)
    expect(SqliteIntegrityCheck).not_to receive(:run)

    load Rails.root.join("config", "initializers", "sqlite_integrity_check.rb").to_s
  end
end
