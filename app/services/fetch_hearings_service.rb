# frozen_string_literal: true

require "faraday"
require "fileutils"
require "json"

# @lat: [[hearing-fetch-pipeline#How the three stages came to be shaped this way]]
class FetchHearingsService
  def initialize(bill: nil, bill_run: nil, run: nil, mode: :discover, faraday_conn: nil, attachment_conn: nil)
    @bill = bill
    @bill_run = bill_run
    @run = run
    @mode = mode
    @faraday_conn = faraday_conn || default_faraday_conn
    @attachment_conn = attachment_conn || faraday_conn || default_attachment_faraday_conn
    # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
    @event_ids = {} #: Hash[Integer, Array[Integer]]
    @matter_exists = {} #: Hash[Integer, bool]
    @unswept_event_ids = [] #: Array[Integer]
    @unswept_collections = [] #: Array[String]
    # @lat: [[testimony-content-classification-stage3#Two dispositions, and they are not symmetric]]
    @content_pending_ids = [] #: Array[Integer]
    @content_unreadable_ids = [] #: Array[Integer]
    # @lat: [[testimony-content-classification-stage3#content_verdict_keeps?: reading the three guard clauses as guards]]
    @content_denied_records = [] #: Array[attachment_record]
    # @lat: [[hearing-attachment-discovery-internals#The three discovery counts, and why they can look like the same number]]
    @discovery_found = 0
    @discovery_pdf_candidates = 0
    @discovery_kept = 0
    @discovery_recorded = 0
  end

  # @lat: [[hearing-fetch-pipeline#:backfill_missing is kept even though nothing calls it today]]
  def call
    case @mode
    when :discover
      call_discover
    else
      raise StageError, "FetchHearingsService: unknown mode #{@mode.inspect}"
    end
  end

  def sway_locale
    target_bill = @bill || @run&.bill
    target_bill&.sway_locale || @run&.effective_sway_locale || resolve_default_sway_locale
  end

  # @lat: [[attachment-attempts#Attachment download attempts#Later retry selection rules]]
  def retry_single_attachment!(attachment_id:, url:, filename:)
    target_bill = @bill
    raise ArgumentError, "FetchHearingsService#retry_single_attachment! requires a bill" if target_bill.nil?
    return false unless target_bill

    coerced_id = coerce_attachment_id(attachment_id)
    raise ArgumentError, "FetchHearingsService#retry_single_attachment! invalid attachment_id: #{attachment_id.inspect}" if coerced_id.nil?

    record = {
      "id" => coerced_id,
      "filename" => filename.to_s,
      "name" => filename.to_s,
      "url" => url,
      "source_endpoint" => MATTER_ATTACHMENTS_SOURCE,
      "event_id" => nil,
      "event_item_id" => nil,
      "download_status" => DOWNLOAD_STATUS_PENDING,
      "extraction_status" => EXTRACTION_STATUS_PENDING,
      "error" => nil
    }

    locale_name = sway_locale&.name
    download_attachments!([record], sway_locale: locale_name, bill: target_bill)
    return false unless record["download_status"] == DOWNLOAD_STATUS_SUCCEEDED

    extract_attachments!([record], sway_locale: locale_name)
    merged = reconcile_records_for_retry(record)
    persist_testimony!(target_bill, merged)
    true
  end

  private

  def reconcile_records_for_retry(retried_record)
    bill = @bill
    existing_mirror = bill&.bill_llm_provisioning&.testimony_attachments || []
    retried_id_str = retried_record["id"]&.to_s

    found = false
    merged = []

    existing_mirror.each do |entry|
      next unless entry.is_a?(Hash)
      entry_id = entry["attachment_id"]&.to_s
      next if entry_id.blank?

      if retried_id_str.present? && entry_id == retried_id_str
        merged << retried_record
        found = true
      else
        merged << {
          "id" => coerce_attachment_id(entry_id),
          "filename" => entry["filename"].to_s,
          "name" => entry["filename"].to_s,
          "url" => nil,
          "download_status" => entry["download_status"],
          "extraction_status" => entry["extraction_status"],
          "error" => entry["error"]
        }
      end
    end

    merged << retried_record unless found
    merged
  end

  # @lat: [[legislation-pipeline#How a stage resolves its SwayLocale]]
  def resolve_default_sway_locale
    sway_locale = SwayLocale.resolve_by_computed_name(LegislationIngestionService::DEFAULT_LOCALE_NAME)
    sway_locale || raise(StageError, "fetch_hearings: no default SwayLocale found")
  end

  def default_faraday_conn
    target_bill = @bill || @run&.bill
    locale = target_bill&.sway_locale || @run&.effective_sway_locale || resolve_default_sway_locale
    rules = begin
      locale&.jurisdiction_rules
    rescue
      nil
    end
    hearings_rules = begin
      rules&.hearings_rules
    rescue RSpec::Mocks::MockExpectationError, NoMethodError
      nil
    end

    if rules.nil? || hearings_rules.nil?
      locale_name = locale&.name || "nil"
      raise StageError, "fetch_hearings: connection rules lack a valid retrieval strategy or base_url for #{locale_name}"
    end

    retrieval = hearings_rules&.dig(:retrieval) || hearings_rules&.dig("retrieval") ||
      hearings_rules&.dig(:retrieval_strategy) || hearings_rules&.dig("retrieval_strategy") ||
      hearings_rules&.dig(:engine) || hearings_rules&.dig("engine")
    base_url = hearings_rules&.dig(:base_url) || hearings_rules&.dig("base_url")

    if retrieval.to_s.in?(%w[congress_dot_gov congress])
      Sway::FaradayStack.congress_gov
    elsif retrieval.to_s == "legistar"
      Sway::FaradayStack.legistar
    elsif retrieval.to_s == "unavailable"
      Faraday.new
    elsif base_url.present?
      Sway::FaradayStack.build(base_url: base_url.to_s)
    else
      locale_name = locale&.name || "nil"
      raise StageError, "fetch_hearings: connection rules lack a valid retrieval strategy or base_url for #{locale_name}"
    end
  end

  # @lat: [[download-bounds#Download bounds]]
  def default_attachment_faraday_conn
    target_bill = @bill || @run&.bill
    locale = target_bill&.sway_locale || @run&.effective_sway_locale || resolve_default_sway_locale
    rules = begin
      locale&.jurisdiction_rules
    rescue
      nil
    end
    hearings_rules = begin
      rules&.hearings_rules
    rescue RSpec::Mocks::MockExpectationError, NoMethodError
      nil
    end

    if rules.nil? || hearings_rules.nil?
      locale_name = locale&.name || "nil"
      raise StageError, "fetch_hearings: connection rules lack a valid retrieval strategy or base_url for #{locale_name}"
    end

    retrieval = hearings_rules&.dig(:retrieval) || hearings_rules&.dig("retrieval") ||
      hearings_rules&.dig(:retrieval_strategy) || hearings_rules&.dig("retrieval_strategy") ||
      hearings_rules&.dig(:engine) || hearings_rules&.dig("engine")
    base_url = hearings_rules&.dig(:base_url) || hearings_rules&.dig("base_url")

    if retrieval.to_s.in?(%w[congress_dot_gov congress])
      Sway::FaradayStack.congress_gov
    elsif retrieval.to_s == "legistar"
      Sway::FaradayStack.legistar_attachment
    elsif retrieval.to_s == "unavailable"
      Faraday.new
    elsif base_url.present?
      Faraday.new(url: base_url.to_s)
    else
      locale_name = locale&.name || "nil"
      raise StageError, "fetch_hearings: connection rules lack a valid retrieval strategy or base_url for #{locale_name}"
    end
  end

  def adapter
    @adapter ||= begin
      locale = sway_locale
      rules = locale&.jurisdiction_rules
      hearings_rules = begin
        rules&.hearings_rules
      rescue RSpec::Mocks::MockExpectationError, NoMethodError
        nil
      end
      cfg = hearings_rules || (rules.is_a?(SwayLocale::JurisdictionRules) ? rules : nil) || {}
      Legislation::Adapters::GenericHearingsAdapter.new(
        cfg,
        connection: @faraday_conn,
        attachment_connection: @attachment_conn,
        service: self
      )
    end
  end

  # @lat: [[attachment-fetch-safety-checks#One shared seam for the host allowlist]]
  def attachment_fetch
    adapter.attachment_fetch
  end

  # @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
  def call_discover
    raise StageError, "FetchHearingsService(:discover): bill kwarg is required" if @bill.nil?

    bill = @bill #: Bill
    if legistar_jurisdiction?
      matter_id = bill.try(:matter_id) || lookup_matter_id_from_metadata(bill)
      matter_id_int = coerce_matter_id!(matter_id)

      event_ids =
        begin
          event_ids_for_matter!(matter_id_int)
        rescue => e
          if e.class.name.include?("HttpError") && e.respond_to?(:status) && e.status != 404
            raise BillProcessingError, "fetch_hearings: HTTP #{e.status} for bill ##{bill.id}"
          elsif e.class.name.include?("ParseError")
            memoize_no_events(matter_id_int, "ParseError on a 2xx body")
            []
          elsif e.is_a?(BillProcessingError)
            raise e
          else
            raise BillProcessingError, "fetch_hearings: #{e.class.name}: #{e.message.to_s[0, 500]}"
          end
        end

      verify_matter_exists!(bill, matter_id_int) if event_ids.empty?

      hearings = event_ids.filter_map { |event_id| fetch_hearing_event(event_id) }
        .map { |event| event_to_hearing_hash(event) }

      sway_locale_name = bill.sway_locale&.name
      attachment_records = discover_attachments(matter_id_int, sway_locale_id: bill.sway_locale_id)
      download_attachments!(attachment_records, sway_locale: sway_locale_name)
      extract_attachments!(attachment_records, sway_locale: sway_locale_name)
      attachment_records = classify_attachment_contents!(
        attachment_records,
        sway_locale: sway_locale_name,
        sway_locale_id: bill.sway_locale_id
      )
      persist_testimony!(bill, attachment_records)

      write_artifact(bill, hearings, attachment_records + @content_denied_records)
      hearings
    else
      adapter.discover_hearings(bill: bill, sway_locale: bill.sway_locale, faraday_conn: @faraday_conn, service: self) #: untyped
    end
  end

  def legistar_jurisdiction?
    target_bill = @bill || @run&.bill
    locale = target_bill&.sway_locale || @run&.effective_sway_locale
    rules = begin
      locale&.jurisdiction_rules
    rescue
      nil
    end
    hearings_rules = begin
      rules&.hearings_rules
    rescue RSpec::Mocks::MockExpectationError, NoMethodError
      nil
    end
    retrieval = hearings_rules&.dig(:retrieval) || hearings_rules&.dig("retrieval") ||
      hearings_rules&.dig(:retrieval_strategy) || hearings_rules&.dig("retrieval_strategy") ||
      hearings_rules&.dig(:engine) || hearings_rules&.dig("engine")
    retrieval.to_s == "legistar"
  end

  # @lat: [[hearing-attachment-discovery-internals#matter_id: why it is coerced strictly, twice]]
  MATTER_ID_MAX = (2**31) - 1 #: Integer
  private_constant :MATTER_ID_MAX

  # @lat: [[hearing-attachment-discovery-internals#Attachment deduplication and provenance ordering]]
  PROVENANCE_RANK_MISSING = MATTER_ID_MAX + 1
  private_constant :PROVENANCE_RANK_MISSING

  MATTER_ATTACHMENTS_SOURCE = "matter_attachments"
  EVENT_ITEM_ATTACHMENTS_SOURCE = "event_item_matter_attachments"
  private_constant :MATTER_ATTACHMENTS_SOURCE, :EVENT_ITEM_ATTACHMENTS_SOURCE

  # @lat: [[testimony-attachment-status-values#Contributing vs. non-contributing statuses]]
  DOWNLOAD_STATUS_PENDING = "pending"
  DOWNLOAD_STATUS_FAILED = "failed"
  DOWNLOAD_STATUS_SUCCEEDED = "succeeded"
  DOWNLOAD_STATUS_NOT_ATTEMPTED = "not_attempted"
  DOWNLOAD_STATUS_SKIPPED_BUDGET = "skipped_time_budget"
  EXTRACTION_STATUS_PENDING = "pending"
  EXTRACTION_STATUS_SUCCEEDED = "succeeded"
  EXTRACTION_STATUS_FAILED = "extraction_failed"
  EXTRACTION_STATUS_REUSED = "reused_prior_run"
  EXTRACTION_STATUS_SKIPPED = "skipped_download_failed"
  EXTRACTION_STATUS_SKIPPED_BUDGET = "skipped_time_budget"
  EXTRACTION_STATUS_NOT_ATTEMPTED = "not_attempted"
  EXTRACTION_STATUS_CONTENT_DENIED = "content_denied"
  CONTRIBUTING_EXTRACTION_STATUSES = [EXTRACTION_STATUS_SUCCEEDED, EXTRACTION_STATUS_REUSED].freeze

  private_constant :DOWNLOAD_STATUS_PENDING, :DOWNLOAD_STATUS_FAILED, :DOWNLOAD_STATUS_SUCCEEDED,
    :DOWNLOAD_STATUS_NOT_ATTEMPTED, :DOWNLOAD_STATUS_SKIPPED_BUDGET,
    :EXTRACTION_STATUS_PENDING, :EXTRACTION_STATUS_SUCCEEDED, :EXTRACTION_STATUS_FAILED,
    :EXTRACTION_STATUS_REUSED, :EXTRACTION_STATUS_SKIPPED, :EXTRACTION_STATUS_SKIPPED_BUDGET,
    :EXTRACTION_STATUS_NOT_ATTEMPTED, :EXTRACTION_STATUS_CONTENT_DENIED,
    :CONTRIBUTING_EXTRACTION_STATUSES

  # @lat: [[hearing-attachment-discovery-internals#The three discovery counts, and why they can look like the same number]]
  MAX_ATTACHMENT_CANDIDATES = 200
  private_constant :MAX_ATTACHMENT_CANDIDATES

  # @lat: [[hearing-fetch-pipeline#Two per-bill time budgets, and why they are start-by deadlines]]
  EXTRACTION_BUDGET_SECONDS = 30 * 60
  private_constant :EXTRACTION_BUDGET_SECONDS

  # @lat: [[hearing-fetch-pipeline#Two per-bill time budgets, and why they are start-by deadlines]]
  DOWNLOAD_BUDGET_SECONDS = 15 * 60
  private_constant :DOWNLOAD_BUDGET_SECONDS

  # @lat: [[testimony-composition-size-limits#Three size bounds, one per layer (as the service stands today)]]
  MAX_ATTACHMENT_TEXT_CHARS = 500_000

  # @lat: [[testimony-composition-size-limits#The per-bill cap, and why per-attachment caps do not add up to it]]
  MAX_TESTIMONY_ATTACHMENT_TEXT_CHARS = 2_000_000

  # @lat: [[testimony-composition-size-limits#Three size bounds, one per layer (as the service stands today)]]
  MAX_COMPOSED_TESTIMONY_CHARS = 8_000_000

  # @lat: [[testimony-composition-size-limits#CLASSIFICATION_READ_BYTES: reading whole sidecars for classification would OOM the Pi]]
  CLASSIFICATION_READ_BYTES = Testimony::ClassificationPromptBuilder::MAX_DOCUMENT_CHARS * 4
  private_constant :CLASSIFICATION_READ_BYTES

  TEXT_TRUNCATION_NOTICE =
    "\n\n[... truncated: this attachment's extracted text exceeded the " \
    "per-attachment size cap ...]"

  COMPOSED_TRUNCATION_NOTICE =
    "\n\n[... truncated: the composed testimony for this bill exceeded the " \
    "per-bill size cap ...]"

  private_constant :TEXT_TRUNCATION_NOTICE, :COMPOSED_TRUNCATION_NOTICE

  # @lat: [[bill-text-filter-history#What the flag was]]
  # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
  def discover_attachments(matter_id_int, sway_locale_id:)
    matter_entries = fetch_matter_attachments(matter_id_int).map do |raw|
      {raw: raw, source_endpoint: MATTER_ATTACHMENTS_SOURCE, event_id: nil, event_item_id: nil} #: attachment_entry
    end

    union = dedupe_attachment_entries(matter_entries + fetch_event_item_matter_attachments(matter_id_int))

    # @lat: [[hearing-attachment-discovery-internals#Truncation drops attachments by accident of order, not by value]]
    @discovery_found = union.size

    pdf_entries = union.select { |entry| pdf_attachment?(entry[:raw]) }

    @discovery_pdf_candidates = pdf_entries.size
    if pdf_entries.size > MAX_ATTACHMENT_CANDIDATES
      SwayLogging.warn(
        "[FetchHearingsService] attachment discovery truncated for matter_id=#{matter_id_int}: " \
          "#{pdf_entries.size} PDF candidates found (of #{union.size} attachments), " \
          "keeping first #{MAX_ATTACHMENT_CANDIDATES}"
      )
      pdf_entries = pdf_entries.first(MAX_ATTACHMENT_CANDIDATES)
    end
    @discovery_kept = pdf_entries.size

    keep = testimony_verdicts(pdf_entries, sway_locale_id: sway_locale_id)

    records = pdf_entries
      .select { |entry| keep_entry?(entry, keep) }
      .map { |entry| normalize_attachment_entry(entry) }

    # @lat: [[hearing-attachment-discovery-internals#The three discovery counts, and why they can look like the same number]]
    @discovery_recorded = records.size
    records
  end

  # @lat: [[hearing-attachment-discovery-internals#Why a malformed attachment id still surfaces as a failed download, not a dropped record]]
  def keep_entry?(entry, keep)
    id = coerce_attachment_id(entry[:raw]["MatterAttachmentId"])
    return true if id.nil?

    keep.fetch(id, true)
  end

  # @lat: [[testimony-content-classification-stage3#content_verdict_keeps?: reading the three guard clauses as guards]]
  def testimony_verdicts(entries, sway_locale_id:)
    candidates = entries.filter_map do |entry|
      id = coerce_attachment_id(entry[:raw]["MatterAttachmentId"])
      next if id.nil?

      {
        "id" => id,
        "name" => entry[:raw]["MatterAttachmentName"].to_s,
        "source_endpoint" => entry[:source_endpoint]
      } #: Testimony::AttachmentClassifier::candidate
    end
    return {} if candidates.empty?

    prefiltered = testimony_classifier.prefilter(candidates, sway_locale_id: sway_locale_id)
    @content_pending_ids = prefiltered[:undecided].filter_map { |candidate| candidate["id"] }
    prefiltered[:verdicts]
  end

  # @lat: [[testimony-content-classification-stage3#Two dispositions, and they are not symmetric]]
  def classify_attachment_contents!(records, sway_locale:, sway_locale_id:)
    pending = @content_pending_ids
    return records if pending.empty?

    candidates = records.filter_map do |record|
      id = record["id"]
      next if id.nil?
      next unless pending.include?(id)

      # @lat: [[testimony-composition-size-limits#CLASSIFICATION_READ_BYTES: reading whole sidecars for classification would OOM the Pi]]
      text = read_attachment_txt(record, sway_locale: sway_locale, max_bytes: CLASSIFICATION_READ_BYTES).to_s
      if text.strip.empty?
        mark_content_unreadable(record, id)
        next
      end

      {
        "id" => id,
        "name" => record["name"],
        "source_endpoint" => record["source_endpoint"],
        "text" => text
      } #: Testimony::AttachmentClassifier::content_candidate
    end

    verdicts = testimony_classifier.classify_contents(candidates, sway_locale_id: sway_locale_id)
    kept, denied = records.partition { |record| content_verdict_keeps?(record, verdicts) }
    denied.each { |record| mark_content_denied(record) }
    @content_denied_records = denied
    kept
  end

  # @lat: [[testimony-content-classification-stage3#content_verdict_keeps?: reading the three guard clauses as guards]]
  def mark_content_denied(record)
    record["extraction_status"] = EXTRACTION_STATUS_CONTENT_DENIED
    record["error"] = "the model read this document and judged it not testimony, so its text is " \
      "withheld from the composed testimony. If that is wrong, paste the text into Supplemental " \
      "testimony — the saved verdict is only re-asked when the classification prompt changes"
  end

  # @lat: [[testimony-content-classification-stage3#Two dispositions, and they are not symmetric]]
  def mark_content_unreadable(record, id)
    @content_unreadable_ids << id
    return unless CONTRIBUTING_EXTRACTION_STATUSES.include?(record["extraction_status"])

    record["extraction_status"] = EXTRACTION_STATUS_FAILED
    record["error"] = "the classifier could not read this attachment's extracted text, so the " \
      "text is withheld from extracted_testimony this run — re-run fetch_hearings"
  end

  # @lat: [[testimony-content-classification-stage3#content_verdict_keeps?: reading the three guard clauses as guards]]
  def content_verdict_keeps?(record, verdicts)
    id = record["id"]
    return true if id.nil?
    return true unless @content_pending_ids.include?(id)
    return true if @content_unreadable_ids.include?(id)

    verdicts.fetch(id, true)
  end

  def testimony_classifier
    @testimony_classifier ||= Testimony::AttachmentClassifier.build
  end

  # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
  def fetch_matter_attachments(matter_id_int)
    attachments =
      begin
        if adapter.respond_to?(:legistar_client)
          adapter.legistar_client.matter_attachments(matter_id_int)
        else
          adapter.matter_attachments(matter_id_int)
        end
      rescue => e
        mark_collection_unswept(matter_attachments_route(matter_id_int), e.class.name.demodulize)
        return []
      end
    unless attachments.is_a?(Array)
      # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
      mark_collection_unswept(
        matter_attachments_route(matter_id_int),
        "2xx body was #{attachments.class.name}, not an Array"
      )
      return []
    end

    attachments.select { |raw| raw.is_a?(::Hash) }
  rescue Faraday::Error, BillProcessingError => e
    mark_collection_unswept(matter_attachments_route(matter_id_int), e.class.name.demodulize)
    []
  end

  # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
  def matter_attachments_route(matter_id_int)
    "Matters/#{matter_id_int}/Attachments"
  end

  def matter_histories_route(matter_id_int)
    "Matters/#{matter_id_int}/Histories"
  end

  # @lat: [[hearing-attachment-discovery-internals#fetch_hearing_event: an unrecorded response shape, and the only 404 signal in the pipeline]]
  def event_ids_for_matter!(matter_id_int)
    memoized = @event_ids[matter_id_int]
    return memoized unless memoized.nil?

    histories =
      if adapter.respond_to?(:legistar_client)
        adapter.legistar_client.matter_histories(matter_id_int)
      else
        adapter.matter_histories(matter_id_int)
      end
    ids =
      if histories.is_a?(Array)
        histories
          .filter_map { |h| h["MatterHistoryEventId"] if h.is_a?(::Hash) }
          .filter_map { |raw_event_id| coerce_attachment_id(raw_event_id) }
          .uniq
      else
        # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
        mark_collection_unswept(
          matter_histories_route(matter_id_int),
          "2xx body was #{histories.class.name}, not an Array"
        )
        [] #: Array[Integer]
      end
    @event_ids[matter_id_int] = ids
  end

  # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
  def memoize_no_events(matter_id_int, reason)
    mark_collection_unswept(matter_histories_route(matter_id_int), reason)
    @event_ids[matter_id_int] = []
  end

  # @lat: [[legistar-client-design#Why an HttpError on a Histories fetch has no fail-soft 404 branch]]
  def verify_matter_exists!(bill, matter_id_int)
    return if matter_exists?(matter_id_int)

    raise BillProcessingError,
      "fetch_hearings: matter_id #{matter_id_int} does not exist upstream " \
      "(Matters/#{matter_id_int} -> 404) for bill ##{bill.id} — the empty Histories " \
      "collection is a stale metadata.json id, not an absence of hearings; recorded nothing"
  end

  # @lat: [[legistar-client-design#Why an HttpError on a Histories fetch has no fail-soft 404 branch]]
  def matter_exists?(matter_id_int)
    memoized = @matter_exists[matter_id_int]
    return memoized unless memoized.nil?

    @matter_exists[matter_id_int] = adapter.matter_exists?(matter_id_int)
  end

  # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
  def event_ids_for_matter(matter_id_int)
    event_ids_for_matter!(matter_id_int)
  rescue Faraday::Error, BillProcessingError => e
    memoize_no_events(matter_id_int, e.class.name.demodulize)
  rescue => e
    memoize_no_events(matter_id_int, e.class.name.demodulize)
  end

  # @lat: [[hearing-attachment-discovery-internals#fetch_hearing_event: an unrecorded response shape, and the only 404 signal in the pipeline]]
  def fetch_hearing_event(event_id)
    event =
      begin
        if adapter.respond_to?(:legistar_client)
          adapter.legistar_client.get("Events/#{event_id}")
        else
          adapter.hearing_event(event_id)
        end
      rescue => e
        if e.respond_to?(:status) && e.status == 404
          mark_event_unswept(event_id, "Events/#{event_id} -> HTTP #{e.status}")
        end
        nil
      end
    event.is_a?(::Hash) ? event : nil
  rescue Faraday::Error, BillProcessingError
    nil
  end

  # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
  def mark_event_unswept(event_id, reason)
    return if @unswept_event_ids.include?(event_id)

    @unswept_event_ids << event_id
    SwayLogging.warn(
      "[FetchHearingsService] event #{event_id} left unswept for matter of bill " \
        "##{@bill&.id}: #{reason} — this run cannot say what attachments that event carries, " \
        "so its testimony verdict is not authoritative"
    )
  end

  # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
  def mark_collection_unswept(route, reason)
    return if @unswept_collections.any? { |entry| entry.start_with?("#{route} ") }

    @unswept_collections << "#{route} (#{reason})"
    SwayLogging.warn(
      "[FetchHearingsService] collection #{route} left unread for bill ##{@bill&.id}: #{reason} " \
        "— this run cannot say what that collection contains, so its testimony verdict is not " \
        "authoritative"
    )
  end

  # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
  def fetch_event_item_matter_attachments(matter_id_int)
    event_ids_for_matter(matter_id_int).flat_map do |event_id|
      next [] if @unswept_event_ids.include?(event_id)

      items =
        begin
          if adapter.respond_to?(:legistar_client)
            adapter.legistar_client.get_raw("Events/#{event_id}/EventItems", "Attachments" => 1)
          else
            adapter.event_items(event_id)
          end
        rescue => e
          mark_event_unswept(event_id, "Events/#{event_id}/EventItems -> #{e.class.name.demodulize}")
          []
        end
      unless items.is_a?(Array)
        # @lat: [[hearing-attachment-discovery-internals#Unswept bookkeeping: recording what this run could NOT read]]
        mark_event_unswept(
          event_id,
          "Events/#{event_id}/EventItems -> 2xx body was #{items.class.name}, not an Array"
        )
        next []
      end

      items
        .select { |item| item.is_a?(::Hash) && item["EventItemMatterId"] == matter_id_int }
        .flat_map { |item| event_item_attachment_entries(item, event_id) }
    end
  end

  def event_item_attachment_entries(item, event_id)
    raw_attachments = item["EventItemMatterAttachments"]
    return [] unless raw_attachments.is_a?(::Array)

    # @lat: [[hearing-attachment-discovery-internals#Attachment deduplication and provenance ordering]]
    event_item_id_raw = item["EventItemId"]
    event_item_id = event_item_id_raw.is_a?(::Integer) ? coerce_attachment_id(event_item_id_raw) : nil

    raw_attachments.filter_map do |raw|
      next unless raw.is_a?(::Hash)

      {raw: raw, source_endpoint: EVENT_ITEM_ATTACHMENTS_SOURCE, event_id: event_id, event_item_id: event_item_id} #: attachment_entry
    end
  end

  # @lat: [[hearing-attachment-discovery-internals#Attachment deduplication and provenance ordering]]
  def dedupe_attachment_entries(entries)
    entries
      .group_by { |entry| dedupe_key(entry) }
      .values
      .map { |group| group.min_by { |entry| entry_provenance_rank(entry) } || group.fetch(0) }
  end

  # @lat: [[hearing-attachment-discovery-internals#Attachment deduplication and provenance ordering]]
  def dedupe_key(entry)
    uncoercible = [:uncoercible, entry.object_id] #: [Symbol, Integer]
    coerce_attachment_id(entry[:raw]["MatterAttachmentId"]) || uncoercible
  end

  # @lat: [[hearing-attachment-discovery-internals#Attachment deduplication and provenance ordering]]
  def entry_provenance_rank(entry)
    [entry[:event_id] ? 0 : 1, entry[:event_id] || 0, entry[:event_item_id] || PROVENANCE_RANK_MISSING]
  end

  # @lat: [[bill-text-filter-history#Why the .pdf gate cleans the name before testing it, and what it replaced]]
  def pdf_attachment?(raw)
    Legislation::Paths.upstream_file_name(raw["MatterAttachmentFileName"])
      .to_s.downcase.end_with?(".pdf")
  end

  # @lat: [[hearing-attachment-discovery-internals#Why a malformed attachment id still surfaces as a failed download, not a dropped record]]
  # @lat: [[bill-text-filter-history#What the flag was]]
  def normalize_attachment_entry(entry)
    raw = entry[:raw]
    filename = Legislation::Paths.upstream_file_name(raw["MatterAttachmentFileName"]).to_s
    # @lat: [[admin-mirror-display-vs-identity#The same split exists one layer down, on the raw attachment record]]
    name = Sway::Utf8.scrub(raw["MatterAttachmentName"].to_s)
    url_raw = raw["MatterAttachmentHyperlink"]
    url = url_raw.is_a?(::String) ? url_raw : nil
    coerced_id = coerce_attachment_id(raw["MatterAttachmentId"])

    if coerced_id.nil?
      return {
        "id" => nil,
        "filename" => filename,
        "name" => name,
        "url" => url,
        "source_endpoint" => entry[:source_endpoint],
        "event_id" => entry[:event_id],
        "event_item_id" => entry[:event_item_id],
        "download_status" => DOWNLOAD_STATUS_FAILED,
        "extraction_status" => EXTRACTION_STATUS_PENDING,
        "error" => "attachment id invalid: #{raw["MatterAttachmentId"].inspect}"[0, 300]
      }
    end

    {
      "id" => coerced_id,
      "filename" => filename,
      "name" => name,
      "url" => url,
      "source_endpoint" => entry[:source_endpoint],
      "event_id" => entry[:event_id],
      "event_item_id" => entry[:event_item_id],
      "download_status" => DOWNLOAD_STATUS_PENDING,
      "extraction_status" => EXTRACTION_STATUS_PENDING,
      "error" => nil
    }
  end

  # @lat: [[hearing-attachment-discovery-internals#matter_id: why it is coerced strictly, twice]]
  def coerce_attachment_id(value)
    case value
    when ::Integer
      value if value.positive? && value <= MATTER_ID_MAX
    when ::String
      return nil unless value.match?(/\A\d{1,10}\z/)

      coerced = Integer(value, 10)
      coerced if coerced.positive? && coerced <= MATTER_ID_MAX
    end
  end

  def coerce_matter_id!(value)
    case value
    when ::Integer
      raise BillProcessingError, "fetch_hearings: matter_id must be > 0 (got #{value})" if value <= 0
      raise BillProcessingError, "fetch_hearings: matter_id out of range (got #{value})" if value > MATTER_ID_MAX

      value
    when ::String
      raise BillProcessingError, "fetch_hearings: matter_id must be 1-10 digits (got #{value.inspect})" unless value.match?(/\A\d{1,10}\z/)

      coerced = Integer(value, 10)
      raise BillProcessingError, "fetch_hearings: matter_id must be > 0 (got #{value})" if coerced <= 0
      raise BillProcessingError, "fetch_hearings: matter_id out of range (got #{coerced})" if coerced > MATTER_ID_MAX

      coerced
    else
      raise BillProcessingError, "fetch_hearings: matter_id must be Integer-coercible (got #{value.class.name})"
    end
  end

  # @lat: [[hearing-fetch-pipeline#event_to_hearing_hash: a dead type check, and why every field is coerced]]
  def event_to_hearing_hash(event)
    {
      "EventId" => coerce_attachment_id(event["EventId"]),
      "EventDate" => legistar_string(event["EventDate"]),
      "EventTime" => legistar_string(event["EventTime"]),
      "EventLocation" => legistar_string(event["EventLocation"]),
      "EventBodyName" => legistar_string(event["EventBodyName"])
    }
  end

  # @lat: [[hearing-fetch-pipeline#event_to_hearing_hash: a dead type check, and why every field is coerced]]
  def legistar_string(value)
    value if value.is_a?(::String)
  end

  # @lat: [[hearing-attachment-discovery-internals#matter_id: why it is coerced strictly, twice]]
  def lookup_matter_id_from_metadata(bill)
    metadata_path = Legislation::Paths.bill_metadata_file(bill.external_id, sway_locale: bill.sway_locale&.name)
    unless metadata_path.exist?
      raise BillProcessingError,
        "fetch_hearings: no metadata.json at #{metadata_path}. " \
        "The fetch-bills stage writes that file — include it in the run for this bill."
    end

    matter_id = Legislation::BillMetadata.matter_id(bill.external_id, sway_locale: bill.sway_locale&.name)
    if matter_id.nil?
      raise BillProcessingError,
        "fetch_hearings: matter_id missing or not Integer-coercible in metadata.json"
    end

    matter_id #: (Integer | String)
  end

  # @lat: [[hearing-fetch-pipeline#The shape of the per-bill artifact]]
  def write_artifact(bill, hearings, attachment_records)
    artifact_path = Legislation::Paths.hearings_file(bill.external_id, sway_locale: bill.sway_locale&.name)
    payload = {
      "events" => hearings,
      "attachments" => attachment_records,
      "attachment_discovery" => discovery_census
    }
    Legislation::ArtifactWriter.write(
      artifact_path,
      JSON.pretty_generate(payload),
      stage: "fetch_hearings",
      atomic: false
    )
  end

  # @lat: [[hearing-attachment-discovery-internals#The three discovery counts, and why they can look like the same number]]
  def discovery_census
    found = @discovery_found
    kept = @discovery_kept
    {
      "found" => found,
      "kept" => kept,
      "recorded" => @discovery_recorded,
      "truncated" => @discovery_pdf_candidates > kept,
      "events_unswept" => @unswept_event_ids.sort,
      "collections_unswept" => @unswept_collections.sort
    }
  end

  # @lat: [[hearing-attachment-discovery-internals#The three discovery counts, and why they can look like the same number]]
  def truncation_mirror_entry
    census = discovery_census
    return nil unless census["truncated"]

    pdf_candidates = @discovery_pdf_candidates
    {
      "filename" => "(#{pdf_candidates - census["kept"]} attachments not fetched)",
      "download_status" => DOWNLOAD_STATUS_NOT_ATTEMPTED,
      "extraction_status" => EXTRACTION_STATUS_NOT_ATTEMPTED,
      "error" => "discovery found #{pdf_candidates} PDF attachments (of #{census["found"]} " \
        "total) and kept the first #{census["kept"]} (MAX_ATTACHMENT_CANDIDATES). The dropped " \
        "ones are whichever arrived last, not the least relevant — paste any missing " \
        "testimony by hand."
    } #: attachment_status
  end

  # @lat: [[attachment-attempts#Attachment download attempts]]
  def download_attachments!(records, sway_locale:, bill: @bill)
    # @lat: [[attachment-attempts#Attachment download attempts]]
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DOWNLOAD_BUDGET_SECONDS

    records.each do |record|
      next unless record["download_status"] == DOWNLOAD_STATUS_PENDING

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        record["download_status"] = DOWNLOAD_STATUS_SKIPPED_BUDGET
        record["error"] =
          "this bill's #{DOWNLOAD_BUDGET_SECONDS}s download budget was exhausted before " \
          "this attachment was reached — re-run fetch_hearings, or paste the testimony by hand"
        record_download_attempt(record, bill: bill)
        next
      end

      url = record["url"]
      if url.nil?
        record["download_status"] = DOWNLOAD_STATUS_FAILED
        record["error"] = "attachment has no download url"
        record_download_attempt(record, bill: bill)
        next
      end

      # @lat: [[download-bounds#Download bounds]]
      response =
        begin
          attachment_fetch.call(url)
        rescue Legistar::AttachmentFetch::Rejected => e
          record["download_status"] = DOWNLOAD_STATUS_FAILED
          record["error"] = e.message.to_s[0, 300]
          record_download_attempt(record, bill: bill)
          next
        rescue Faraday::Error => e
          record["download_status"] = DOWNLOAD_STATUS_FAILED
          record["error"] = "#{e.class.name}: #{e.message.to_s[0, 200]}"
          record_download_attempt(record, bill: bill)
          next
        end

      unless response.status.between?(200, 299)
        record["download_status"] = DOWNLOAD_STATUS_FAILED
        record["error"] = "HTTP #{response.status}"[0, 300]
        record_download_attempt(record, bill: bill)
        next
      end

      # @lat: [[download-bounds#Download bounds]]
      bytes = response.body.to_s

      unless bytes.start_with?(FetchBillsService::PDF_MAGIC_BYTES)
        record["download_status"] = DOWNLOAD_STATUS_FAILED
        record["error"] = "response body is not a PDF (magic-byte check failed)"
        record_download_attempt(record, bill: bill)
        next
      end

      # @lat: [[attachment-attempts#Attachment download attempts]]
      begin
        Legislation::Paths.attachment_dir(sway_locale: sway_locale).mkpath
        File.binwrite(attachment_pdf_path(record, sway_locale: sway_locale), bytes)
      rescue SystemCallError, IOError => e
        record["download_status"] = DOWNLOAD_STATUS_FAILED
        record["error"] = "write failed: #{e.class.name.demodulize}: #{e.message.to_s[0, 200]}"
        record_download_attempt(record, bill: bill)
        next
      end

      record["download_status"] = DOWNLOAD_STATUS_SUCCEEDED
      record["error"] = nil
      record_download_attempt(record, bill: bill)
    end
  end

  def record_download_attempt(record, bill: @bill)
    target_bill = bill || @bill
    PipelineActivityLogger.log_attachment_download_attempt!(
      record: record,
      bill: target_bill
    )
  rescue => e
    SwayLogging.warn(
      "[FetchHearingsService] failed to record attachment download attempt for " \
      "attachment #{record["id"] || record["filename"]} (bill #{target_bill&.external_id}): " \
      "#{e.class.name}: #{e.message}"
    )
  end

  # @lat: [[testimony-persistence-disk-composition#Why extract_attachments! is where the single extraction retry lives]]
  def extract_attachments!(records, sway_locale:)
    # @lat: [[hearing-fetch-pipeline#Two per-bill time budgets, and why they are start-by deadlines]]
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + EXTRACTION_BUDGET_SECONDS

    records.each do |record|
      if record["download_status"] == DOWNLOAD_STATUS_SKIPPED_BUDGET
        record["extraction_status"] = EXTRACTION_STATUS_NOT_ATTEMPTED
      elsif record["download_status"] != DOWNLOAD_STATUS_SUCCEEDED
        record["extraction_status"] = EXTRACTION_STATUS_SKIPPED
      elsif Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        record["extraction_status"] = EXTRACTION_STATUS_SKIPPED_BUDGET
        record["error"] =
          "this bill's #{EXTRACTION_BUDGET_SECONDS}s extraction budget was exhausted before " \
          "this attachment was reached — re-run fetch_hearings, or paste the testimony by hand"
      else
        extract_one_attachment(record, sway_locale: sway_locale)
      end

      # @lat: [[testimony-persistence-disk-composition#A removed parameter]]
      next if record["extraction_status"] == EXTRACTION_STATUS_SUCCEEDED
      next unless attachment_txt_present?(record, sway_locale: sway_locale)

      # @lat: [[testimony-persistence-disk-composition#Why the reused-attachment error message is rewritten, not just the status]]
      record["error"] = reuse_error(record["error"])
      record["extraction_status"] = EXTRACTION_STATUS_REUSED
    end
    nil
  end

  # @lat: [[testimony-persistence-disk-composition#Why the reused-attachment error message is rewritten, not just the status]]
  def reuse_error(prior_error)
    reason = prior_error.to_s.strip
    message =
      if reason.empty?
        "this run did not re-extract; showing text captured by a previous run"
      else
        "this run could not re-extract (#{reason}); showing text captured by a previous run"
      end
    message[0, 300].to_s
  end

  # @lat: [[testimony-persistence-disk-composition#Why attachment_txt_present? asks the reader's own question, not a stand-in for it]]
  def attachment_txt_present?(record, sway_locale:)
    text = read_attachment_txt(record, sway_locale: sway_locale)
    !text.nil? && !text.strip.empty?
  end

  def extract_one_attachment(record, sway_locale:)
    text = attempt_extraction(record, sway_locale: sway_locale)
    return nil if text.nil?

    if text.strip.empty?
      record["extraction_status"] = EXTRACTION_STATUS_FAILED
      record["error"] = "extraction produced no text layer (no OCR attempted)"
      return nil
    end

    text, truncation_note = cap_extracted_text(text, attachment_text_char_cap(record, sway_locale: sway_locale))

    # @lat: [[testimony-persistence-disk-composition#Why a failed sidecar write returns nil instead of reporting success]]
    begin
      File.write(attachment_txt_path(record, sway_locale: sway_locale), text)
    rescue SystemCallError, IOError => e
      record["extraction_status"] = EXTRACTION_STATUS_FAILED
      record["error"] = "write failed: #{e.class.name.demodulize}: #{e.message.to_s[0, 200]}"
      return nil
    end

    record["extraction_status"] = EXTRACTION_STATUS_SUCCEEDED
    # @lat: [[testimony-attachment-warning-lists#A cut-short extraction is a third answer]]
    record["error"] = truncation_note
    text
  end

  # @lat: [[testimony-composition-size-limits#Three size bounds, one per layer (as the service stands today)]]
  # @lat: [[testimony-composition-size-limits#A second, higher cap for name-confirmed testimony#Why the routing proxy is a name match, not the model verdict]]
  def cap_extracted_text(text, char_cap = MAX_ATTACHMENT_TEXT_CHARS)
    return [text, nil] if text.length <= char_cap

    [
      text[0, char_cap].to_s + TEXT_TRUNCATION_NOTICE,
      "extracted text truncated to #{char_cap} chars (was #{text.length})"
    ]
  end

  # @lat: [[testimony-attachment-rules#Testimony attachment rules#Filename rule boundaries]]
  def attachment_text_char_cap(record, sway_locale:)
    return MAX_TESTIMONY_ATTACHMENT_TEXT_CHARS if Testimony::NameRules.classify(record["name"], sway_locale: sway_locale) == :testimony
    MAX_ATTACHMENT_TEXT_CHARS
  end

  def attempt_extraction(record, sway_locale:)
    TestimonyTextExtractor.new(attachment_pdf_path(record, sway_locale: sway_locale).to_s).call
  rescue TestimonyTextExtractor::ExtractionFailed
    begin
      TestimonyTextExtractor.new(attachment_pdf_path(record, sway_locale: sway_locale).to_s).call
    rescue TestimonyTextExtractor::ExtractionFailed => e
      record["extraction_status"] = EXTRACTION_STATUS_FAILED
      record["error"] = "#{e.class.name}: #{e.message.to_s[0, 300]}"
      nil
    end
  end

  # @lat: [[testimony-persistence-disk-composition#Why persist_testimony! always rewrites testimony_attachments]]
  def persist_testimony!(bill, records)
    provisioning = bill.bill_llm_provisioning || bill.build_bill_llm_provisioning
    mirror = attachment_status_mirror(records)

    composed = compose_testimony_from_disk(records, sway_locale: bill.sway_locale&.name)
    case testimony_write_decision(records, provisioning, composed)
    when :replace
      if composed != provisioning.extracted_testimony
        # @lat: [[testimony-write-decision#Inside :replace: losing one attachment while composing something is still evidence loss]]
        now = ::Time.zone.now
        if evidence_withdrawn?(provisioning.testimony_attachments, mirror)
          provisioning.draft_org_positions =
            BillLlmProvisioning.drafts_with_evidence_retracted(provisioning.draft_org_positions, at: now)
        end
        provisioning.extracted_testimony = composed
        provisioning.testimony_fetched_at = now
      end
    when :retract
      # @lat: [[testimony-write-decision#Inside :retract: why the column is cleared AND the drafts built on it are flagged]]
      now = ::Time.zone.now
      provisioning.extracted_testimony = nil
      provisioning.testimony_fetched_at = now
      provisioning.draft_org_positions =
        BillLlmProvisioning.drafts_with_evidence_retracted(provisioning.draft_org_positions, at: now)
    when :retain_with_notice
      # @lat: [[testimony-mirror-rule#Why the carried-forward row wins over this run's row, on overlap]]
      carried = carried_forward_mirror_entries(provisioning.testimony_attachments)
      carried_ids = carried.filter_map { |entry| entry["attachment_id"] }.reject(&:empty?)
      mirror = carried +
        mirror.reject { |entry| carried_ids.include?(entry["attachment_id"].to_s) } +
        [incomplete_sweep_mirror_entry(records) ||
          (records.any? ? no_contributing_candidates_mirror_entry(records) : retained_testimony_mirror_entry)]
    end
    provisioning.testimony_attachments = mirror
    provisioning.save!
  # @lat: [[hearing-fetch-pipeline#Why an unexpected write failure becomes BillProcessingError]]
  rescue ActiveRecord::ActiveRecordError => e
    raise BillProcessingError,
      "fetch_hearings: testimony persist failed: #{e.class.name.demodulize}: #{e.message.to_s[0, 300]}"
  end

  # @lat: [[testimony-write-decision-outcomes#The four outcomes]]
  # @lat: [[testimony-write-decision#nothing_qualified?: distinguishing "nothing qualifies" from "nothing worked"]]
  def testimony_write_decision(records, provisioning, composed)
    return :replace if composed.present?
    return :none if provisioning.extracted_testimony.blank?
    return :retract if nothing_qualified?(records)
    return :retain_with_notice if discovery_returned_nothing?(records) || sweep_incomplete?(records)

    # @lat: [[testimony-mirror-rule#Why :retain_with_notice also fires when every candidate produced no text]]
    if records.none? { |record| CONTRIBUTING_EXTRACTION_STATUSES.include?(record["extraction_status"]) }
      return :retain_with_notice
    end

    # @lat: [[testimony-mirror-rule#Why :retain_with_notice also fires when every candidate produced no text]]
    :none
  end

  # @lat: [[evidence-withdrawal-detection#Why a substring check does not work here]]
  def evidence_withdrawn?(previous_mirror, mirror)
    previous = contributing_entries(previous_mirror)
    current = contributing_entries(mirror)

    # @lat: [[evidence-withdrawal-detection#Three limits, written down rather than left to be rediscovered]]
    return false unless comparable_by_id?(previous, current)

    previous_ids = previous.map { |e| e["attachment_id"].to_s }.uniq
    current_ids = current.map { |e| e["attachment_id"].to_s }.uniq
    (previous_ids - current_ids).any?
  end

  # @lat: [[evidence-withdrawal-detection#Three limits, written down rather than left to be rediscovered]]
  def comparable_by_id?(previous, current)
    (previous + current).all? { |entry| entry["attachment_id"].present? }
  end

  # @lat: [[testimony-mirror-rule#Why made-up rows can never be mistaken for a withdrawn attachment]]
  def contributing_entries(mirror)
    return [] unless mirror.is_a?(::Array)

    mirror.filter_map do |entry|
      next unless entry.is_a?(::Hash)
      next unless CONTRIBUTING_EXTRACTION_STATUSES.include?(entry["extraction_status"])

      entry
    end
  end

  # @lat: [[testimony-write-decision#nothing_qualified?: distinguishing "nothing qualifies" from "nothing worked"]]
  def nothing_qualified?(records)
    records.empty? && @discovery_found.positive? && !sweep_incomplete?(records)
  end

  # @lat: [[testimony-write-decision#nothing_qualified?: distinguishing "nothing qualifies" from "nothing worked"]]
  def sweep_incomplete?(records)
    records.empty? && (@unswept_event_ids.any? || @unswept_collections.any?)
  end

  # @lat: [[testimony-write-decision#nothing_qualified?: distinguishing "nothing qualifies" from "nothing worked"]]
  def discovery_returned_nothing?(records)
    records.empty? && !@discovery_found.positive?
  end

  # @lat: [[testimony-mirror-rule#Why each made-up mirror row has its own wording]]
  def retained_testimony_mirror_entry
    {
      "filename" => "(no attachments discovered this run)",
      "download_status" => DOWNLOAD_STATUS_NOT_ATTEMPTED,
      "extraction_status" => EXTRACTION_STATUS_NOT_ATTEMPTED,
      "error" => "Legistar returned no attachments for this bill on this run, so nothing was " \
        "downloaded or extracted. The testimony shown below was captured by a PRIOR run and is " \
        "retained deliberately: a bill with genuinely no attachments and a Legistar outage look " \
        "identical from here. Re-run fetch_hearings to confirm it is still upstream."
    } #: attachment_status
  end

  # @lat: [[testimony-mirror-rule#Why each made-up mirror row has its own wording]]
  def no_contributing_candidates_mirror_entry(records)
    total = records.length + @content_denied_records.length
    {
      "filename" => "(#{total} attachment(s) discovered, none produced text)",
      "download_status" => DOWNLOAD_STATUS_NOT_ATTEMPTED,
      "extraction_status" => EXTRACTION_STATUS_NOT_ATTEMPTED,
      "error" => "This run discovered #{total} attachment(s) and none of them contributed text " \
        "— each row above gives its own reason, whether the fetch failed or the model judged " \
        "the document not to be testimony. The testimony shown below was captured by a PRIOR " \
        "run and is retained deliberately: this run established nothing about what is upstream. " \
        "Re-run fetch_hearings, or paste the testimony text into Supplemental testimony below."
    } #: attachment_status
  end

  # @lat: [[testimony-mirror-rule#Why each made-up mirror row has its own wording]]
  def incomplete_sweep_mirror_entry(records)
    return nil unless sweep_incomplete?(records)
    return unswept_events_mirror_entry if @unswept_event_ids.any?

    unswept_collections_mirror_entry
  end

  # @lat: [[testimony-mirror-rule#Why each made-up mirror row has its own wording]]
  def unswept_collections_mirror_entry
    routes = @unswept_collections.sort.join("; ")
    {
      "filename" => "(#{@unswept_collections.length} attachment collection(s) not read this run)",
      "download_status" => DOWNLOAD_STATUS_NOT_ATTEMPTED,
      "extraction_status" => EXTRACTION_STATUS_NOT_ATTEMPTED,
      "error" => "This run could not read #{routes}. Attachment discovery unions two Legistar " \
        "collections and degrades an unreadable one to empty, so the attachment count below is a " \
        "FLOOR, not a census — a bill whose remaining collection holds only bill text looks " \
        "identical to a bill with no testimony. The testimony shown below was captured by a PRIOR " \
        "run and is retained deliberately; re-run fetch_hearings, and check that endpoint in " \
        "Legistar if it repeats."
    } #: attachment_status
  end

  def unswept_events_mirror_entry
    ids = @unswept_event_ids.sort.join(", ")
    {
      "filename" => "(#{@unswept_event_ids.length} hearing event(s) not read this run)",
      "download_status" => DOWNLOAD_STATUS_NOT_ATTEMPTED,
      "extraction_status" => EXTRACTION_STATUS_NOT_ATTEMPTED,
      "error" => "Matters/<id>/Histories named hearing event(s) #{ids}, but this run could not " \
        "read their agenda items — the event either does not resolve upstream or its EventItems " \
        "fetch failed. A Legistar sub-resource answers 200 [] for an event that no longer " \
        "resolves, so an empty attachment set from one of these events proves nothing. The " \
        "testimony shown below was captured by a PRIOR run and is retained deliberately; " \
        "re-run fetch_hearings, and check those event ids in Legistar if it repeats."
    } #: attachment_status
  end

  # @lat: [[testimony-composition-size-limits#A second, higher cap for name-confirmed testimony#Why the composed cap had to move too]]
  def compose_testimony_from_disk(records, sway_locale:)
    composed = +""

    records.each do |record|
      # @lat: [[testimony-content-classification-stage3#Two dispositions, and they are not symmetric]]
      next if @content_unreadable_ids.include?(record["id"])

      text = read_attachment_txt(record, sway_locale: sway_locale)
      next if text.nil? || text.strip.empty?

      composed << "\n\n" unless composed.empty?
      composed << text
      if composed.length > MAX_COMPOSED_TESTIMONY_CHARS
        return composed[0, MAX_COMPOSED_TESTIMONY_CHARS].to_s + COMPOSED_TRUNCATION_NOTICE
      end
    end

    composed
  end

  # @lat: [[testimony-composition-size-limits#A second, higher cap for name-confirmed testimony#Why the composed cap had to move too]]
  def read_attachment_txt(record, sway_locale:, max_bytes: attachment_text_char_cap(record, sway_locale: sway_locale) * 4)
    return nil if record["id"].nil?

    path = attachment_txt_path(record, sway_locale: sway_locale)
    return nil unless path.exist?

    text, _truncation_note = cap_extracted_text(
      Sway::Utf8.scrub(path.binread(max_bytes)),
      attachment_text_char_cap(record, sway_locale: sway_locale)
    )
    text
  rescue SystemCallError, IOError
    nil
  end

  # @lat: [[admin-mirror-display-vs-identity#filename: a human-readable display label]]
  def attachment_status_mirror(records)
    entries = (records + @content_denied_records).map do |record|
      {
        # @lat: [[admin-mirror-display-vs-identity#filename: a human-readable display label]]
        "filename" => record["name"].presence || record["filename"],
        "attachment_id" => record["id"]&.to_s,
        "download_status" => record["download_status"],
        "extraction_status" => record["extraction_status"],
        "error" => record["error"]
      } #: attachment_status
    end

    entries + [truncation_mirror_entry].compact
  end

  # @lat: [[testimony-mirror-rule#Why the carried-forward row wins over this run's row, on overlap]]
  def carried_forward_mirror_entries(previous_mirror)
    return [] unless previous_mirror.is_a?(::Array)

    previous_mirror.filter_map do |entry|
      next unless entry.is_a?(::Hash)
      next unless CONTRIBUTING_EXTRACTION_STATUSES.include?(entry["extraction_status"])

      {
        "filename" => entry["filename"].to_s,
        "attachment_id" => entry["attachment_id"]&.to_s,
        "download_status" => DOWNLOAD_STATUS_NOT_ATTEMPTED,
        "extraction_status" => EXTRACTION_STATUS_REUSED,
        "error" => nil
      } #: attachment_status
    end
  end

  # @lat: [[hearing-attachment-discovery-internals#Attachment deduplication and provenance ordering]]
  def attachment_basename(record, extension)
    File.basename("attachment-#{record["id"]}.#{extension}")
  end

  def attachment_pdf_path(record, sway_locale:)
    Legislation::Paths.attachment_dir(sway_locale: sway_locale).join(attachment_basename(record, "pdf"))
  end

  def attachment_txt_path(record, sway_locale:)
    Legislation::Paths.attachment_dir(sway_locale: sway_locale).join(attachment_basename(record, "txt"))
  end
end
