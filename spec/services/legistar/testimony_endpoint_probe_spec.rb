# frozen_string_literal: true

require "rails_helper"

# Proof, checkable against the real API, that a real Baltimore bill yields
# testimony PDFs from BOTH collections, via Legistar::Client rather than
# raw Faraday, so recorded URLs match production.
RSpec.describe "Legistar testimony endpoint probe" do
  let(:target_bill_file) { "25-0064" }
  let(:cassette_path) { Rails.root.join("spec", "cassettes", "legistar_testimony_endpoint_probe.yml") }

  def non_reader_pdfs(attachments)
    attachments.select do |a|
      a["MatterAttachmentFileName"].to_s.downcase.end_with?(".pdf") &&
        !FetchBillsService::READER_NAME_PATTERN.match?(a["MatterAttachmentName"].to_s)
    end
  end

  it "unions non-Reader testimony PDFs from Matters/Attachments and Events/EventItems (Attachments=1)" do
    matter_candidates = []
    event_item_candidates = []
    # Hoisted out of the cassette block so assertions can name what was
    # probed. probed_matter_id is SEPARATE: nil there would widen the type
    # the client's id arg accepts.
    probed_matter_id = nil
    recorded_event_ids = []

    VCR.use_cassette("legistar_testimony_endpoint_probe") do
      client = Legistar::Client.new

      matters = client.get("Matters", filter: "MatterFile eq '#{target_bill_file}'")
      matter_id = matters.first.fetch("MatterId")
      probed_matter_id = matter_id

      matter_attachments_raw = client.matter_attachments(matter_id)
      matter_attachments = matter_attachments_raw.is_a?(Array) ? matter_attachments_raw : []
      matter_candidates = non_reader_pdfs(matter_attachments)

      # The second collection: event ids come from Matters/{id}/Histories, NOT
      # from Matters/{id}/Events, which does not exist (see the notes at the top
      # of this file).
      histories = client.matter_histories(matter_id)
      recorded_event_ids = histories.filter_map { |h| h["MatterHistoryEventId"] }.uniq

      event_item_attachments = recorded_event_ids.flat_map do |event_id|
        # A STRING key (Attachments => 1) through #get_raw, so #odata_params
        # adds no $ prefix — a symbol key would send the wrong parameter,
        # proven live while recording this.
        items_raw = client.get_raw("Events/#{event_id}/EventItems", "Attachments" => 1)
        items = items_raw.is_a?(Array) ? items_raw : []
        items.select { |i| i["EventItemMatterId"] == matter_id }
          .flat_map { |i| i["EventItemMatterAttachments"] || [] }
      end
      event_item_candidates = non_reader_pdfs(event_item_attachments)
    end

    union_ids = (matter_candidates + event_item_candidates).pluck("MatterAttachmentId").uniq

    # @lat: [[hearing-testimony-census#Event ids come only from a matter's histories]]
    expect(matter_candidates).not_to be_empty,
      "Matters/#{probed_matter_id}/Attachments yielded no non-Reader PDFs for bill #{target_bill_file}"
    expect(event_item_candidates).not_to be_empty,
      "Events/<id>/EventItems yielded no non-Reader PDFs for bill #{target_bill_file} — the shape"

    # The event ids themselves, so a Matters/{id}/Histories response that stops
    # carrying MatterHistoryEventId fails by name rather than silently skipping
    # the whole flat_map.
    expect(recorded_event_ids).not_to be_empty,
      "Matters/#{probed_matter_id}/Histories carried no MatterHistoryEventId, so no event was probed at all"

    expect(union_ids).not_to be_empty,
      "expected >= 1 non-Reader PDF across both collections for bill #{target_bill_file}; " \
      "matter_attachments non-Reader=#{matter_candidates.size} event_item_matter_attachments non-Reader=#{event_item_candidates.size}"

    warn "[testimony probe] matter_attachments non-Reader PDFs: #{matter_candidates.size}; " \
      "event_item_matter_attachments non-Reader PDFs: #{event_item_candidates.size}; " \
      "union non-Reader PDF count: #{union_ids.size}"
  end

  it "recorded the EventItems request with an unprefixed Attachments=1 param (not $Attachments)" do
    cassette = YAML.safe_load_file(cassette_path, aliases: true)
    event_items_uri = cassette["http_interactions"]
      .map { |interaction| interaction["request"]["uri"] }
      .find { |uri| uri.include?("EventItems") }

    expect(event_items_uri).not_to be_nil
    expect(event_items_uri).to include("Attachments=1")
    expect(event_items_uri).not_to include("%24Attachments")
    expect(event_items_uri).not_to include("$Attachments")
  end
end
