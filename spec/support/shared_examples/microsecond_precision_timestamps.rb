# frozen_string_literal: true

# @lat: [[pipeline-activity-log-serialize-entry-quirks#Why created_at is written with iso8601(6), not plain iso8601]]
RSpec.shared_examples "emits microsecond-precision timestamps" do |emit:|
  it "serializes created_at with iso8601(6) microsecond precision" do
    allow(PipelineRunChannel).to receive(:broadcast_to)
    entry = instance_exec(&emit)

    serialized = PipelineActivityLogger.serialize_entry(entry)
    created_at_str = serialized[:created_at]

    # Must match: YYYY-MM-DDTHH:MM:SS.dddddd (6 fractional digits)
    expect(created_at_str).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}/)

    # Must NOT be plain iso8601 (no fractional component after the seconds)
    expect(created_at_str).not_to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^.]/)
  end
end
