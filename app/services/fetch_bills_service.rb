# frozen_string_literal: true

require "faraday"
require "fileutils"
require "json"

# @lat: [[bill-external-id-validation#Bill external ID validation]]
# @lat: [[legislation-path-root-resolution#Where the root comes from]]
class FetchBillsService
  PAGE_SIZE = 1000
  PDF_MAGIC_BYTES = "%PDF".b
  READER_NAME_PATTERN = Legislation::Adapters::GenericLegislationAdapter::READER_NAME_PATTERN

  # @lat: [[legislation-fetch-time-budgets#The two unbounded loops]]
  DISCOVERY_BUDGET_SECONDS = 15 * 60
  private_constant :DISCOVERY_BUDGET_SECONDS

  DOWNLOAD_BUDGET_SECONDS = 30 * 60
  private_constant :DOWNLOAD_BUDGET_SECONDS

  # @lat: [[fetch-bills-service-overview#Why bill_run: stays on the constructor even though this stage never uses it]]
  def initialize(run:, bill_run: nil, mode: :discover, faraday_conn: nil, detail_url_resolver: nil)
    @run = run
    @bill_run = bill_run
    @mode = mode
    @conn = faraday_conn
    @detail_url_resolver = detail_url_resolver
  end

  # @lat: [[fetch-bills-service-overview#Why call writes database rows as part of what looks like a file-fetch stage]]
  # @lat: [[bill-artifact-write-ordering#Bill artifact write ordering]]
  def call
    case @mode
    when :discover
      call_discover
    when :backfill_missing
      call_backfill_missing
    else
      raise StageError, "FetchBillsService: unknown mode #{@mode.inspect}"
    end
  end

  # @lat: [[fetch-bills-seed-from-disk#Why the disk sweep is scoped to this service's own jurisdiction]]
  def seed_from_disk
    metadatas = scope_to_run_bill(read_disk_metadatas)
    return 0 if metadatas.empty?

    seed_ar_rows(metadatas, resolve_sway_locale)
    metadatas.length
  end

  private

  def adapter_for(locale = nil)
    target = resolve_target_locale(locale)
    rules = target&.jurisdiction_rules
    leg_rules = rules&.legislation_rules
    Legislation::Adapters::GenericLegislationAdapter.new(
      leg_rules || rules || {},
      connection: conn,
      service: self
    )
  end

  def call_discover
    sway_locale = resolve_sway_locale
    adapter = adapter_for(sway_locale)
    metadatas = adapter.discover(
      sway_locale: sway_locale,
      start_time: Time.current.to_f,
      budget_seconds: DISCOVERY_BUDGET_SECONDS,
      run_bill: @run&.bill,
      service: self
    ) #: untyped
    # @lat: [[legislation-pipeline#Empty discovery is a stage failure]]
    if metadatas.empty?
      raise EmptyStageError, "fetch_bills: no bills were discovered for #{sway_locale.name}"
    end
    # @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
    seed_ar_rows(metadatas, sway_locale)
    persist_within_budget(metadatas)
    metadatas
  rescue Faraday::Error, BillProcessingError => e
    if e.is_a?(Faraday::Error) || e.message.include?("transport error") || e.message.include?("network error") || e.message.include?("Faraday::")
      # @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
      raise BillProcessingError, "fetch_bills network error: #{e.message.to_s[0, 500]}"
    else
      raise e
    end
  end

  # @lat: [[legislation-pipeline#Upstream jurisdiction adapters]]
  def call_backfill_missing
    run_locale_id = @run&.effective_sway_locale&.id || @run.sway_locale_id || @run.bill&.sway_locale_id
    ready = [] #: Array[[String, String?, Integer | String]]
    undiscovered = [] #: Array[[String, String?]]

    @run.each_pipeline_run_bill do |bill_run|
      bill = Legislation::PipelineBillLookup.find(bill_run.bill_external_id, sway_locale_id: run_locale_id)
      next if bill.nil?
      next if Pipeline::ArtifactPresence.present?("fetch-bills", bill: bill)

      adapter = adapter_for(bill.sway_locale)
      adapter.backfill_bill(bill, ready: ready, undiscovered: undiscovered, service: self)
    end

    unrepaired = undiscovered.reject do |external_id, locale_name|
      locale = resolve_target_locale(locale_name)
      adapter_for(locale).repair_missing_metadata(external_id, locale)
    end
    refuse_when_nothing_was_produced(ready, undiscovered, unrepaired)
    nil
  rescue Faraday::Error, BillProcessingError => e
    if e.is_a?(Faraday::Error) || e.message.include?("transport error") || e.message.include?("network error") || e.message.include?("Faraday::")
      raise BillProcessingError, "fetch_bills (backfill) network error: #{e.message.to_s[0, 500]}"
    else
      raise e
    end
  rescue SystemCallError, IOError => e
    # @lat: [[fetch-bills-backfill-missing-mode#Why the write-failure rescue is kept apart from the network rescue]]
    raise BillProcessingError,
      "fetch_bills (backfill) write failed: #{e.class.name.demodulize}: #{e.message.to_s[0, 300]}"
  rescue Legislation::Paths::UnsafeExternalIdError => e
    SwayLogging.warn("[FetchBillsService] backfill skipped unusable external_id: #{e.message}")
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
  def refuse_when_nothing_was_produced(ready, undiscovered, unrepaired)
    return nil if unrepaired.empty?

    if ready.any? || unrepaired.length < undiscovered.length
      msg = "[FetchBillsService] no bill text for #{bill_id_list(unrepaired)}; those bills end the " \
        "run with no PDF and later stages skip them"
      SwayLogging.warn(msg)
      return nil
    end

    raise EmptyStageError,
      "fetch_bills (backfill): could not acquire bill text for #{bill_id_list(unrepaired)} by name, " \
      "so this run has no bill text to work from."
  end

  # @lat: [[fetch-bills-backfill-missing-mode#Why bill_id_list caps its output]]
  def bill_id_list(pairs, limit: 5)
    names = pairs.first(limit).map { |external_id, _locale_name| external_id }
    names << "and #{pairs.length - limit} more" if pairs.length > limit
    names.join(", ")
  end

  def conn
    @conn ||= default_faraday_conn
  end

  def resolve_target_locale(target_locale = nil)
    if target_locale.is_a?(String)
      SwayLocale.resolve_by_computed_name(target_locale) || resolve_sway_locale
    elsif target_locale.is_a?(SwayLocale) || target_locale.respond_to?(:jurisdiction_rules)
      target_locale
    else
      resolve_sway_locale
    end
  end

  # @lat: [[fetch-bills-service-overview#Why single-bill runs filter the fetched matter list down to one]]
  def scope_to_run_bill(metadatas)
    target = @run.bill&.external_id.to_s.strip
    return metadatas if target.empty?

    metadatas.select { |m| m[:external_id].to_s == target }
  end

  # @lat: [[fetch-bills-seed-from-disk#Why the disk sweep is scoped to this service's own jurisdiction]]
  def read_disk_metadatas
    paths = Pathname.glob(
      artifact_root.join(sway_locale_name, "*", "metadata.json").to_s
    )
    rows = paths.filter_map do |path|
      raw = JSON.parse(path.read)
      next unless raw.is_a?(Hash)

      # @lat: [[bill-external-id-validation#Validation at discovery and disk intake]]
      external_id = Legislation::Paths.external_id_segment(raw["external_id"].to_s)
      matter_id = raw["matter_id"]
      if external_id.nil?
        SwayLogging.warn(
          "[FetchBillsService] skipping metadata.json at #{path}: unusable external_id " \
          "#{raw["external_id"].to_s[0, 120].inspect}"
        )
        next
      end
      next unless matter_id.is_a?(Integer)

      intro = raw["introduction_date"]
      raw_status = raw["status"]
      status = adapter_for(resolve_sway_locale).map_status(raw_status)
      raw_link = raw["link"]
      link = if raw_link.is_a?(String) && !raw_link.include?("LegislationSearch.aspx")
        raw_link.presence
      end
      metadata = {
        external_id: external_id,
        matter_id: matter_id,
        title: raw["title"].to_s,
        introduction_date: intro.is_a?(String) ? intro : nil,
        bill_number: raw["bill_number"].to_s,
        matter_type: raw["matter_type"].to_s,
        pdf_url: raw["pdf_url"].is_a?(String) ? raw["pdf_url"] : nil,
        pdf_filename: raw["pdf_filename"].is_a?(String) ? raw["pdf_filename"] : nil,
        status: status,
        legislator_external_id: raw["legislator_external_id"].is_a?(String) ? raw["legislator_external_id"] : nil,
        chamber: raw["chamber"].is_a?(String) ? raw["chamber"] : nil,
        link: link
      } #: metadata
      metadata
    rescue JSON::ParserError => e
      SwayLogging.warn("[FetchBillsService] skipping unparseable metadata.json at #{path}: #{e.message}")
      next
    rescue SystemCallError, IOError => e
      # @lat: [[fetch-bills-seed-from-disk#Why read_disk_metadatas copies each field across by hand]]
      SwayLogging.warn(
        "[FetchBillsService] skipping unreadable metadata.json at #{path}: #{e.class.name}: #{e.message}"
      )
      next
    end
    rows.sort_by { |m| m[:external_id] }
  end

  # @lat: [[legislation-fetch-time-budgets#The two unbounded loops]]
  def persist_within_budget(metadatas)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DOWNLOAD_BUDGET_SECONDS
    budget_spent = false

    metadatas.each_with_index do |metadata, index|
      if !budget_spent && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        budget_spent = true
        SwayLogging.warn(
          "[FetchBillsService] download budget of #{DOWNLOAD_BUDGET_SECONDS}s used up after " \
          "#{index} of #{metadatas.length} bills; the rest keep their metadata.json and can be " \
          "backfilled"
        )
      end

      # @lat: [[legislation-fetch-time-budgets#Why the download loop keeps writing metadata.json after its budget is spent]]
      persist(metadata, download: !budget_spent)
    end
  end

  def select_primary_attachment(attachments, locale: nil)
    target = locale || sway_locale_name
    adapter_for(target).select_primary_attachment(attachments, target)
  end

  def build_metadata(matter, locale: nil)
    target = locale || sway_locale_name
    adapter_for(target).build_metadata(matter, resolve_target_locale(target), conn)
  end

  def fetch_all_matters(locale: nil)
    target = locale || sway_locale_name
    adapter_for(target).fetch_all_matters(resolve_target_locale(target), conn)
  end

  # @lat: [[legislation-path-root-resolution#Where the root comes from]]
  def artifact_root
    Legislation::Paths.bills_raw
  end

  # @lat: [[bill-external-id-validation#Validating external bill identifiers]]
  # @lat: [[bill-artifact-write-ordering#Persist protects the guarantee at the write itself]]
  def persist(metadata, download: true)
    segment = Legislation::Paths.external_id_segment(metadata[:external_id])
    if segment.nil?
      SwayLogging.warn(
        "[FetchBillsService] persist skipped for bill: unusable external_id #{metadata[:external_id].inspect} " \
        "(not a safe path segment)"
      )
      return nil
    end

    dir = Legislation::Paths.bill_artifact_dir(segment, sway_locale: sway_locale_name)
    FileUtils.mkdir_p(dir)
    File.write(dir.join("metadata.json"), JSON.pretty_generate(metadata))
    download_pdf(dir, metadata[:pdf_url], metadata[:pdf_filename]) if download
  rescue Faraday::Error, SystemCallError, IOError, Legislation::Paths::UnsafeExternalIdError => e
    SwayLogging.warn(
      "[FetchBillsService] persist failed for bill #{metadata[:external_id]} " \
        "(backfillable — AR row is seeded; re-run fetch_bills or let " \
        "mode: :backfill_missing pick it up): #{e.class.name}: #{e.message.to_s[0, 200]}"
    )
    nil
  end

  def download_pdf(dir, pdf_url, pdf_filename)
    return unless pdf_url.is_a?(String) && !pdf_url.empty?
    return unless pdf_filename.is_a?(String) && !pdf_filename.empty?

    adapter = adapter_for(resolve_sway_locale)
    adapter.download_pdf(dir, pdf_url, pdf_filename, connection: conn)
  end

  def default_faraday_conn
    sway_locale = resolve_sway_locale
    rules = begin
      sway_locale&.jurisdiction_rules
    rescue
      nil
    end
    leg_rules = rules&.legislation_rules

    if rules.nil? || leg_rules.nil?
      locale_name = sway_locale&.name || "nil"
      raise StageError, "fetch_bills: connection rules lack a valid retrieval strategy or base_url for #{locale_name}"
    end

    base_url = leg_rules&.dig(:base_url) || leg_rules&.dig("base_url")
    retrieval = leg_rules&.dig(:retrieval) || leg_rules&.dig("retrieval") ||
      leg_rules&.dig(:retrieval_strategy) || leg_rules&.dig("retrieval_strategy") ||
      leg_rules&.dig(:engine) || leg_rules&.dig("engine")

    if retrieval.to_s.in?(%w[congress_dot_gov congress])
      Sway::FaradayStack.congress_gov
    elsif retrieval.to_s == "legistar"
      Sway::FaradayStack.legistar
    elsif base_url.present?
      Sway::FaradayStack.build(base_url: base_url)
    else
      locale_name = sway_locale&.name || "nil"
      raise StageError, "fetch_bills: connection rules lack a valid retrieval strategy or base_url for #{locale_name}"
    end
  end

  # @lat: [[legislation-pipeline#How a stage resolves its SwayLocale]]
  def resolve_sway_locale
    @sway_locale ||= @run&.effective_sway_locale || resolve_default_sway_locale
  end

  # @lat: [[legislation-pipeline#How a stage resolves its SwayLocale]]
  def resolve_default_sway_locale
    sway_locale = SwayLocale.resolve_by_computed_name(LegislationIngestionService::DEFAULT_LOCALE_NAME)
    sway_locale || raise(StageError, "fetch_bills: no default SwayLocale found")
  end

  # @lat: [[legislation-pipeline#How a stage resolves its SwayLocale]]
  def sway_locale_name
    @sway_locale_name ||= resolve_sway_locale.name
  end

  # @lat: [[bill-session-archiving#Bill session archiving#Ingestion and pending work]]
  def seed_ar_rows(metadatas, sway_locale)
    ingestion = LegislationIngestionService.new(run: @run)
    ::ActiveRecord::Base.transaction do
      metadatas.each_with_index do |metadata, idx|
        if Legislation::Paths.external_id_segment(metadata[:external_id]).nil?
          SwayLogging.warn(
            "[FetchBillsService] skipping bill seed: unusable external_id #{metadata[:external_id].inspect}"
          )
          next
        end

        bill_payload = bill_data_from_metadata(metadata, sway_locale)
        next unless ingestion.upsert_bill_payload(bill_payload)

        # @lat: [[legislation-pipeline#Runs, resume and restart#One walk decides the per-bill order]]
        PipelineRunBill.find_or_create_by!(
          legislation_pipeline_run: @run,
          bill_external_id: metadata[:external_id].to_s
        ) do |prb|
          prb.sort_order = idx
          prb.status = "pending"
        end
      end
    end
  end

  # @lat: [[legislation-ingestion#Published sponsor metadata]]
  def bill_data_from_metadata(metadata, sway_locale)
    {
      "external_id" => metadata[:external_id].to_s,
      "title" => metadata[:title].to_s,
      "introduced_date_time_utc" =>
        coerce_introduction_date(metadata[:external_id], metadata[:introduction_date]),
      "sway_locale_external_id" => sway_locale.name,
      "legislator_external_id" => metadata[:legislator_external_id].presence,
      "chamber" => metadata[:chamber].presence,
      "status" => metadata[:status].presence,
      "link" => metadata[:link].presence
    }
  end

  # @lat: [[fetch-bills-introduction-date-coercion#Coercing Legistar's MatterIntroDate]]
  def coerce_introduction_date(external_id, raw)
    case raw
    when nil
      nil
    when String
      begin
        Time.zone.parse(raw)&.iso8601 || warn_intro_date(external_id, raw, "unparseable string")
      rescue ArgumentError => e
        warn_intro_date(external_id, raw, "unparseable string: #{e.message[0, 80]}")
      end
    when Integer
      begin
        Time.zone.at(raw).iso8601
      rescue RangeError, ArgumentError => e
        warn_intro_date(external_id, raw, "out-of-range epoch: #{e.message.to_s[0, 80]}")
      end
    else
      warn_intro_date(external_id, raw, "unexpected type #{raw.class}")
      nil
    end
  end

  def warn_intro_date(external_id, raw, reason)
    SwayLogging.warn(
      "[FetchBillsService] introduction_date for bill " \
        "#{external_id} dropped (#{reason}): #{raw.inspect[0, 80]}"
    )
    nil
  end
end
