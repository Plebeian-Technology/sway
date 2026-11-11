# frozen_string_literal: true

require "rails_helper"

# @lat: [[pipeline-activity-logger-overview#How the logger knows whether a page is about to render#The end-to-end request spec proving the flash round-trip (HIGH-R2-3)]]
RSpec.describe "PipelineActivityLogger Inertia flash round-trip (HIGH-R2-3)", type: :request do
  it "writes flash[:activity_log_entry] that propagates to usePage().props.flash" do
    inertia_version = InertiaRails.configuration.version.to_s
    get "/__inertia_flash_probe/trigger", headers: {
      "X-Inertia" => "true",
      "X-Inertia-Version" => inertia_version
    }

    expect(response).to have_http_status(:ok)

    # The inertia helper (inertia_rails/rspec) surfaces shared props including flash
    expect(inertia).to have_props { |p|
      p[:flash].is_a?(Hash) &&
        p[:flash].key?(:activity_log_entry) || p[:flash].key?("activity_log_entry")
    }

    flash_payload = inertia.props[:flash]
    entry = flash_payload[:activity_log_entry] || flash_payload["activity_log_entry"]

    expect(entry).to be_a(Hash)
    event_type = entry[:event_type] || entry["event_type"]
    severity = entry[:severity] || entry["severity"]
    title = entry[:title] || entry["title"]

    expect(event_type).to eq("orphan_run_deleted")
    expect(severity).to eq("info")
    # The live event names the run it removed; the retired duplicate said only
    # "Orphan run cleaned up".
    expect(title).to match(/\AOrphan run #\d+ removed\z/)

    # Spot-checks a subset of the serialized keys, not the full shape.
    all_keys = entry.keys.map(&:to_s).sort
    expect(all_keys).to include("id", "subject_type", "subject_id", "actor_user_id", "payload", "created_at")
  end
end
