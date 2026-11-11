# frozen_string_literal: true

require "rails_helper"

# @lat: [[production-snapshot-deploy-rehearsal-harness#Why ProductionSnapshot.migrate! is built from the pending-migrations primitives, not the rake-task runner]]
RSpec.describe "Deploy migrate command parity" do
  let(:entrypoint) { Rails.root.join("bin", "docker-entrypoint").read }

  # @lat: [[production-snapshot-deploy-rehearsal-harness#Why the entrypoint runs sway:deploy and database setup only on web server startup]]
  it "runs sway:deploy inside the web server branch rather than unconditionally" do
    expect(entrypoint).to match(%r{^\s*\./bin/rake sway:deploy\s*$})
    expect(entrypoint.index("./bin/rake sway:deploy"))
      .to be > entrypoint.index('if [ "${1}" == "./bin/rails" ] && [ "${2}" == "server" ]; then')
  end

  it "runs sway:deploy before migrating the database" do
    expect(entrypoint.index("./bin/rake sway:deploy"))
      .to be < entrypoint.index("./bin/rails db:migrate:with_data")
    expect(entrypoint.index("./bin/rails db:seed"))
      .to be < entrypoint.index("\nfi\n")
  end

  it "runs the combined schema + data chain the snapshot harness replays" do
    expect(entrypoint).to match(%r{^\s*\./bin/rails db:migrate:with_data\s*$})
  end

  it "never invokes plain db:migrate, which skips db/data" do
    expect(entrypoint).not_to match(%r{^\s*\./bin/rails db:migrate\s*$})
  end

  # @lat: [[production-snapshot-deploy-rehearsal-harness#Why the entrypoint also runs db:prepare and sway:setup_queue_database]]
  it "prepares the second database that holds background jobs" do
    expect(entrypoint).to match(%r{^\s*\./bin/rails db:prepare\s*$})
  end

  it "prepares that database before seeding, which is what needs it" do
    expect(entrypoint.index("./bin/rails db:prepare")).to be < entrypoint.index("./bin/rails db:seed")
  end

  it "repairs a job database left half made by a failed deploy" do
    expect(entrypoint).to match(%r{^\s*\./bin/rails sway:setup_queue_database\s*$})
  end

  it "repairs it before seeding, which is what fails without it" do
    expect(entrypoint.index("./bin/rails sway:setup_queue_database"))
      .to be < entrypoint.index("./bin/rails db:seed")
  end
end
