# frozen_string_literal: true

require "rails_helper"

# @lat: [[spec-top-level-constant-scoping#Why shared spec constants sit above the describe block]]
EXPECTED_ENTRY_KEYS = %w[
  id event_type severity title message subject_type subject_id
  subject_label actor_user_id payload inspect_query created_at
].freeze

RSpec.describe BillsController, type: :request do
  include_context "SessionDouble"

  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill) }

  # Writes pipeline_activity_log_entries straight to the database, around the model's
  # read-only rule.
  def insert_log_entry(overrides = {})
    attrs = {
      "event_type" => "orphan_run_deleted",
      "severity" => "info",
      "title" => "Orphan run cleaned up",
      "message" => "Test entry",
      "payload" => "{}",
      "created_at" => Time.current.to_s
    }.merge(overrides.transform_keys(&:to_s))
    PipelineActivityLogEntry.insert!(attrs)
  end

  def create_log_entries(n)
    n.times.map do |i|
      insert_log_entry(
        "message" => "Test entry #{i}",
        "created_at" => (Time.current - i.seconds).to_s
      )
    end
    PipelineActivityLogEntry.recent_first.limit(n).to_a
  end

  before { sign_in admin }

  it "(A) first page: 50 entries returned, has_more: true, next_cursor present" do
    create_log_entries(55)
    get "/admin/bill_creator/#{bill.id}/pipeline"
    expect(response).to have_http_status(:ok)
    expect(inertia).to render_component(Pages::BILL_CREATOR)

    props = inertia.props
    expect(props[:activity_log_entries].length).to eq(50)
    expect(props[:activity_log_has_more]).to be(true)
    expect(props[:activity_log_next_cursor]).to be_a(String)
    expect(props[:activity_log_next_cursor]).not_to be_empty
  end

  it "(B) cursor follow returns remaining entries, has_more: false" do
    # Create 55 entries so first page has 50, second page has 5
    entries = create_log_entries(55)
    last_entry = entries[49] # 50th entry (0-indexed)
    cursor = Base64.urlsafe_encode64(
      "#{last_entry.created_at.iso8601(6)}|#{last_entry.id}",
      padding: false
    )

    get "/admin/bill_creator/#{bill.id}/pipeline", params: {cursor: cursor}
    expect(response).to have_http_status(:ok)

    props = inertia.props
    expect(props[:activity_log_entries].length).to be <= 10
    expect(props[:activity_log_has_more]).to be(false)
  end

  it "(C) severity=errors filter returns only error-severity entries" do
    insert_log_entry(
      "event_type" => "stage_failed", "severity" => "error",
      "title" => "Stage failed: test", "message" => "error msg"
    )
    insert_log_entry(
      "event_type" => "orphan_run_deleted", "severity" => "info",
      "message" => "info msg"
    )

    get "/admin/bill_creator/#{bill.id}/pipeline", params: {severity: "errors"}
    expect(response).to have_http_status(:ok)

    props = inertia.props
    entries = props[:activity_log_entries]
    expect(entries).not_to be_empty
    expect(entries.pluck(:severity).uniq).to eq(["error"])
  end

  it "(D) window=24h filter returns only entries from last 24h" do
    insert_log_entry(
      "message" => "old entry",
      "created_at" => 48.hours.ago.to_s
    )
    insert_log_entry(
      "message" => "recent entry",
      "created_at" => 1.hour.ago.to_s
    )

    get "/admin/bill_creator/#{bill.id}/pipeline", params: {window: "24h"}
    expect(response).to have_http_status(:ok)

    props = inertia.props
    entries = props[:activity_log_entries]
    messages = entries.pluck(:message)
    expect(messages).to include("recent entry")
    expect(messages).not_to include("old entry")
    entries.each do |e|
      expect(Time.iso8601(e[:created_at])).to be > 24.hours.ago
    end
  end

  it "(E) subject=this_bill filter returns entries for this bill only" do
    other_bill = create(:bill)

    insert_log_entry(
      "message" => "this bill entry",
      "subject_type" => "Bill", "subject_id" => bill.id.to_s
    )
    insert_log_entry(
      "message" => "other bill entry",
      "subject_type" => "Bill", "subject_id" => other_bill.id.to_s
    )

    get "/admin/bill_creator/#{bill.id}/pipeline", params: {subject: "this_bill"}
    expect(response).to have_http_status(:ok)

    props = inertia.props
    entries = props[:activity_log_entries]
    messages = entries.pluck(:message)
    expect(messages).to include("this bill entry")
    expect(messages).not_to include("other bill entry")
  end

  it "(F) AND combinator: severity=errors AND window=24h narrows results" do
    insert_log_entry(
      "event_type" => "stage_failed", "severity" => "error",
      "title" => "Stage failed: test", "message" => "recent error",
      "created_at" => 1.hour.ago.to_s
    )
    insert_log_entry(
      "event_type" => "stage_failed", "severity" => "error",
      "title" => "Stage failed: test", "message" => "old error",
      "created_at" => 48.hours.ago.to_s
    )
    insert_log_entry(
      "message" => "recent info",
      "created_at" => 1.hour.ago.to_s
    )

    get "/admin/bill_creator/#{bill.id}/pipeline", params: {severity: "errors", window: "24h"}
    expect(response).to have_http_status(:ok)

    props = inertia.props
    messages = props[:activity_log_entries].pluck(:message)
    expect(messages).to include("recent error")
    expect(messages).not_to include("old error")
    expect(messages).not_to include("recent info")
  end

  it "(G) severity=garbage falls back to default (all), no raise" do
    insert_log_entry("message" => "info entry")

    expect {
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {severity: "garbage"}
    }.not_to raise_error

    expect(response).to have_http_status(:ok)
    props = inertia.props
    expect(props[:activity_log_entries]).not_to be_nil
  end

  it "(H) cursor=garbage returns most-recent page, no raise" do
    create_log_entries(3)

    expect {
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {cursor: "not-valid-base64!!!"}
    }.not_to raise_error

    expect(response).to have_http_status(:ok)
    props = inertia.props
    expect(props[:activity_log_entries]).to be_a(Array)
  end

  it "(I) no params → 7d window default, all severities, all bills" do
    insert_log_entry(
      "message" => "within 7d",
      "created_at" => 3.days.ago.to_s
    )
    insert_log_entry(
      "message" => "older than 7d",
      "created_at" => 10.days.ago.to_s
    )

    get "/admin/bill_creator/#{bill.id}/pipeline"
    expect(response).to have_http_status(:ok)

    props = inertia.props
    messages = props[:activity_log_entries].pluck(:message)
    expect(messages).to include("within 7d")
    expect(messages).not_to include("older than 7d")
  end

  it "(J) GET /bills/:id/edit with admin Bearer returns activity_log_entries inline (HIGH-1)" do
    raw_token = "test-bearer-#{SecureRandom.hex(8)}"
    ApiKey.create!(bearer: admin, token: raw_token)

    insert_log_entry("message" => "mobile json entry")

    get "/admin/bill_creator/#{bill.id}/pipeline",
      headers: {"Authorization" => "Bearer #{raw_token}"}

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include("application/json")

    body = JSON.parse(response.body)
    expect(body["activity_log_entries"]).to be_a(Array)
    expect(body["activity_log_has_more"]).not_to be_nil
  end

  it "(K) prop entry keys match PipelineActivityLogger.serialize_entry shape (INFO-2)" do
    insert_log_entry("message" => "key check")

    get "/admin/bill_creator/#{bill.id}/pipeline"
    expect(response).to have_http_status(:ok)

    props = inertia.props
    entries = props[:activity_log_entries]
    expect(entries).not_to be_empty

    entry_keys = entries.first.keys.map(&:to_s).sort
    expect(entry_keys).to eq(EXPECTED_ENTRY_KEYS.sort)
  end
end
