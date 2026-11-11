# frozen_string_literal: true

# @lat: [[legislation-ingestion#The write boundary]]
class LegislationIngestionService
  class IngestionError < RuntimeError; end

  ALLOWED_BILL_COLUMNS = %w[
    title
    chamber
    category
    status
    link
    summary
    introduced_date_time_utc
    active
    legislative_session_id
  ].freeze

  ALLOWED_PROVISIONING_COLUMNS = %w[
    diff_content
    diff_generated_at
    hearings_fetched_at
  ].freeze

  # @lat: [[legislation-ingestion#Locale and chamber resolution]]
  DEFAULT_LOCALE_NAME = "baltimore-maryland-united_states"

  def initialize(run: nil)
    @run = run
  end

  # @lat: [[legislation-ingestion#The write boundary]]
  def upsert_bill_payload(bill_data)
    return nil if bill_data["external_id"].to_s.blank?

    ActiveRecord::Base.transaction do
      bill = upsert_bill(bill_data)
      return nil if bill.nil?

      provisioning_data = bill_data["provisioning"] #: untyped
      upsert_provisioning(bill, provisioning_data) if provisioning_data.is_a?(Hash)
      bill
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
    PipelineActivityLogger.log_ingestion_failure!(
      bill_external_id: bill_data["external_id"].to_s,
      error_message: e.message
    )
    SwayLogging.log_exception(
      "legislation_ingestion.upsert_bill_payload_failed",
      exception: e,
      run_id: @run&.id,
      external_id: bill_data["external_id"]
    )
    raise IngestionError, e.message
  end

  private

  def upsert_bill(bill_data)
    sway_locale = resolve_sway_locale(bill_data)
    return nil if sway_locale.nil?
    return nil if archived_identity?(bill_data, sway_locale)

    begin
      bill = Bill.find_or_initialize_by(
        external_id: bill_data["external_id"],
        sway_locale: sway_locale
      )
      apply_bill_attributes(bill, bill_data, sway_locale)
      bill.save! if bill.new_record? || bill.changed?
      bill
    rescue ActiveRecord::RecordNotUnique
      # @lat: [[legislation-ingestion#The write boundary]]
      bill = Bill.find_by!(
        external_id: bill_data["external_id"],
        sway_locale: sway_locale
      )
      apply_bill_attributes(bill, bill_data, sway_locale)
      bill.save! if bill.changed?
      bill
    end
  end

  # @lat: [[bill-session-archiving#Bill session archiving#Ingestion and pending work]]
  def archived_identity?(bill_data, sway_locale)
    Bill.unscoped.where(external_id: bill_data["external_id"], sway_locale: sway_locale)
      .where.not(archived_at: nil).exists?
  end

  def apply_bill_attributes(bill, bill_data, sway_locale)
    bill_data.slice(*ALLOWED_BILL_COLUMNS).each do |key, value|
      next if value.nil?
      bill.public_send("#{key}=", value)
    end

    if bill.chamber.blank?
      resolved_chamber = resolve_chamber(bill_data, sway_locale)
      bill.chamber = resolved_chamber if resolved_chamber
    end
    if bill_data["legislator_external_id"].present? || bill.legislator.nil?
      bill.legislator = resolve_legislator(bill_data, sway_locale, bill.chamber)
    end

    # @lat: [[legislation-ingestion#Required values]]
    bill.title ||= bill_data["external_id"].to_s
    bill.summary = Bill::SUMMARY_PLACEHOLDER if bill.summary.blank?
    bill.category = "Ordinance" if bill.category.blank?
    bill.status ||= "committee"
    # @lat: [[legistar-detail-url-resolution#Ingestion pipeline integration and fallback elimination]]
    bill.introduced_date_time_utc ||= Time.current

    # @lat: [[legislation-ingestion#Legislative session assignment]]
    explicit_session_id = bill_data[:legislative_session_id] || bill_data["legislative_session_id"]
    if explicit_session_id.present?
      bill.legislative_session_id = explicit_session_id
    elsif bill.introduced_date_time_utc.present? && (locale = bill.sway_locale || sway_locale).present?
      bill.legislative_session = locale.legislative_session_for_date(bill.introduced_date_time_utc.to_date)
    end
  end

  def upsert_provisioning(bill, provisioning_data)
    provisioning = bill.bill_llm_provisioning || bill.build_bill_llm_provisioning

    attrs = provisioning_data.slice(*ALLOWED_PROVISIONING_COLUMNS)
    attrs.each { |k, v| provisioning.public_send("#{k}=", v) }

    provisioning.save! if provisioning.new_record? || provisioning.changed?
    provisioning
  end

  def resolve_sway_locale(bill_data)
    locale_name = bill_data["sway_locale_external_id"].presence || DEFAULT_LOCALE_NAME
    # @lat: [[legislation-ingestion#Locale and chamber resolution]]
    @all_locales ||= SwayLocale.all.to_a
    @all_locales.find { |l| l.name == locale_name }
  end

  # @lat: [[legislation-ingestion#Locale and chamber resolution]]
  def resolve_chamber(bill_data, sway_locale)
    rules = sway_locale&.declared_jurisdiction_rules
    external_id = bill_data["external_id"].to_s.strip
    patterns = rules&.legislation_rules&.dig(:chamber_patterns) ||
      rules&.legislation_rules&.dig(:metadata_mapping, :chamber_patterns)

    if patterns.is_a?(Hash) && external_id.present?
      patterns.each do |chamber, pattern|
        next if pattern.blank?

        begin
          return chamber.to_s if external_id.match?(Regexp.new(pattern.to_s, Regexp::IGNORECASE))
        rescue RegexpError
          next
        end
      end
    end

    rules&.default_bill_chamber.presence
  end

  # @lat: [[legislation-ingestion#Published sponsor metadata]]
  def resolve_legislator(bill_data, sway_locale, chamber)
    external_id = bill_data["legislator_external_id"].to_s.presence
    if external_id
      return sway_locale.legislators(false).find_by(external_id: external_id) ||
          raise(IngestionError, "No legislator with external_id=#{external_id} found for sway_locale=#{sway_locale.name}. Seed the jurisdiction roster before ingesting this bill.")
    end
    fallback_legislator(sway_locale, chamber)
  end

  # @lat: [[legislation-ingestion#Declared fallback associations]]
  def fallback_legislator(sway_locale, chamber)
    declaration = SwayLocale::PipelineSponsorRegistry.for(sway_locale.name, chamber) ||
      raise(IngestionError,
        "No fallback legislator declared for sway_locale=#{sway_locale.name}, chamber=#{chamber}. " \
        "Supply `legislator_external_id` in the payload.")

    term_title = declaration.fetch(:term_title)
    role = declaration.fetch(:role)
    external_id = declaration[:external_id]
    cache = (@fallback_cache ||= {})
    cache[[sway_locale.id, chamber]] ||= begin
      candidates = sway_locale.legislators.joins(active_term: :district)
        .where(legislator_terms: {title: term_title}, districts: {sway_locale_id: sway_locale.id})
      candidates = candidates.where(external_id: external_id) if external_id
      candidates.first || raise(IngestionError,
        "No current #{role} legislator found for sway_locale=#{sway_locale.name}, chamber=#{chamber}. " \
        "Seed legislators before ingesting pipeline payloads, or supply `legislator_external_id` in the payload.")
    end
  end
end
