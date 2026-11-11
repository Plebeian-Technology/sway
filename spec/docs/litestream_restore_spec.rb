# frozen_string_literal: true

require "rails_helper"

# Keeps docs/litestream-restore.md from drifting away from the code it
# describes. It is a guard against drift, not a test of the prose — every
# expectation reads a constant off ReplicationLagCheckJob rather than typing
# the text a second time, so a change to one without the other goes red.
RSpec.describe "docs/litestream-restore.md" do
  let(:doc) { Rails.root.join("docs", "litestream-restore.md").read }

  it "quotes the stall alarm exactly as the job sends it" do
    expect(doc).to include(ReplicationLagCheckJob::STALL_ALARM), <<~MESSAGE
      docs/litestream-restore.md does not contain the exact text of
      ReplicationLagCheckJob::STALL_ALARM. Either the constant changed and the
      doc needs the same edit, or the doc's copy picked up a typo. Quote the
      constant's current value word for word.
    MESSAGE
  end

  it "quotes the read-failure alarm exactly as the job sends it" do
    expect(doc).to include(ReplicationLagCheckJob::READ_FAILURE_ALARM), <<~MESSAGE
      docs/litestream-restore.md does not contain the exact text of
      ReplicationLagCheckJob::READ_FAILURE_ALARM. Either the constant changed
      and the doc needs the same edit, or the doc's copy picked up a typo.
      Quote the constant's current value word for word.
    MESSAGE
  end

  it "quotes the empty-listing alarm exactly as the job sends it" do
    expect(doc).to include(ReplicationLagCheckJob::EMPTY_LISTING_ALARM), <<~MESSAGE
      docs/litestream-restore.md does not contain the exact text of
      ReplicationLagCheckJob::EMPTY_LISTING_ALARM. Either the constant changed
      and the doc needs the same edit, or the doc's copy picked up a typo.
      Quote the constant's current value word for word.
    MESSAGE
  end

  it "quotes the recovery message exactly as the job sends it" do
    expect(doc).to include(ReplicationLagCheckJob::RECOVERY_MESSAGE), <<~MESSAGE
      docs/litestream-restore.md does not contain the exact text of
      ReplicationLagCheckJob::RECOVERY_MESSAGE. Either the constant changed
      and the doc needs the same edit, or the doc's copy picked up a typo.
      Quote the constant's current value word for word.
    MESSAGE
  end

  it "names the cron monitor's slug exactly as the job sets it" do
    expect(doc).to include(ReplicationLagCheckJob::MONITOR_SLUG), <<~MESSAGE
      docs/litestream-restore.md does not contain
      ReplicationLagCheckJob::MONITOR_SLUG. The monitor is runtime state that
      lives only in the Sentry project — nothing in this repository can
      rebuild it, which is why the slug has to be written down here. If the
      slug changed, update the doc to match.
    MESSAGE
  end

  it "does not claim a healthy replica reports a recent transaction and no repeated errors" do
    expect(doc.downcase).not_to include("healthy replica"), <<~MESSAGE
      docs/litestream-restore.md still contains "healthy replica" somewhere.
      That claim can read as healthy while every upload fails, because the
      field it relied on advances on an upload ATTEMPT, not a successful
      one. Remove it — the three alarm constants above are what a reader
      should trust instead.
    MESSAGE
  end

  it "does not tell the reader to run the copier's own status subcommand" do
    expect(doc).not_to match(/^docker exec litestream litestream status\b/), <<~MESSAGE
      docs/litestream-restore.md has a line starting with
      `docker exec litestream litestream status`. That command reports the
      local position and the write-ahead-log size, not the copy's position,
      and it can report "replicating" while every upload fails. Do not
      present it as something to run — remove the line, or move it out of
      any fenced command block if it is only being named as something not
      to run.
    MESSAGE
  end

  it "does not tell the reader to run a hand-run Rails command for checking replication" do
    expect(doc).not_to match(/bin\/rails (litestream|replication)|rake (litestream|replication)/), <<~MESSAGE
      docs/litestream-restore.md names a bin/rails or rake command for
      checking replication. This phase deliberately adds none: every
      fault announces itself through the three alarms within 30 minutes with
      nobody watching. Remove the command.
    MESSAGE
  end

  it "still says the litestream container is distroless" do
    expect(doc).to include("distroless"), <<~MESSAGE
      docs/litestream-restore.md no longer says the litestream container is
      distroless. That fact is still true after the rewrite — `docker exec`
      still has to invoke the binary directly, since there is no shell
      inside the container. Restore the paragraph.
    MESSAGE
  end

  it "still explains that authentication fails on every attempt rather than when the config is read" do
    expect(doc).to include("fails on every attempt"), <<~MESSAGE
      docs/litestream-restore.md no longer explains that an authentication
      fault fails on every attempt rather than when the config is read. That
      fact is still true, and it is now the explanation behind the stall and
      read-failure alarms — restore the paragraph.
    MESSAGE
  end
end
