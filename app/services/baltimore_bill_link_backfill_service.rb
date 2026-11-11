# frozen_string_literal: true

# @lat: [[legistar-detail-url-resolution#Backfill procedure for stored Baltimore bills]]
class BaltimoreBillLinkBackfillService
  class PersistenceError < StandardError; end

  GENERIC_SEARCH_URL = "https://baltimore.legistar.com/LegislationSearch.aspx"
  DEFAULT_LOCALE = "baltimore-maryland-united_states"

  def self.call(...)
    new(...).call
  end

  def initialize(
    sway_locale: nil,
    locale: nil,
    client: nil,
    detail_url_resolver: nil,
    resolver: nil,
    logger: SwayLogging,
    raise_on_failure: false,
    **kwargs
  )
    resolved_locale = sway_locale || locale
    @sway_locale = resolved_locale ||
      SwayLocale.find_by_name_parts(DEFAULT_LOCALE) || # rubocop:disable Rails/DynamicFindBy
      SwayLocale.find_by(city: "baltimore")
    client_name = @sway_locale&.jurisdiction_rules&.legislation_rules&.dig(:client)&.to_s.presence || "baltimore"
    resolved_client = client || kwargs.find { |k, _| k.to_s.end_with?("client") }&.last
    @client = resolved_client || Legistar::Client.new(client: client_name)
    @detail_url_resolver = detail_url_resolver || resolver || Legistar::DetailUrlResolver.new
    @logger = logger
    @raise_on_failure = raise_on_failure
  end

  def call
    stats = {
      total: 0,
      processed: 0,
      resolved: 0,
      cleared: 0,
      cleared_to_nil: 0,
      failed: 0
    }

    if @sway_locale.nil?
      @logger.warn("[BaltimoreBillLinkBackfillService] Baltimore SwayLocale not found")
      return stats
    end

    scope = Bill.where(sway_locale: @sway_locale, link: GENERIC_SEARCH_URL).order(:id)
    stats[:total] = scope.count

    scope.find_each do |bill|
      stats[:processed] += 1
      process_bill(bill, stats)
    rescue => e
      stats[:failed] += 1
      @logger.warn(
        "[BaltimoreBillLinkBackfillService] bill_id=#{bill.id} external_id=#{bill.external_id} " \
        "failed backfill: #{e.class}: #{e.message}"
      )
    end

    @logger.info(
      "[BaltimoreBillLinkBackfillService] completed backfill: " \
      "processed=#{stats[:processed]} resolved=#{stats[:resolved]} " \
      "cleared=#{stats[:cleared]} failed=#{stats[:failed]}"
    )

    if @raise_on_failure && stats[:failed].positive?
      raise PersistenceError, "[BaltimoreBillLinkBackfillService] #{stats[:failed]} #{"bill".pluralize(stats[:failed])} failed persistence"
    end

    stats
  end

  private

  def process_bill(bill, stats)
    matter_id = begin
      find_matter_id(bill)
    rescue => e
      @logger.warn(
        "[BaltimoreBillLinkBackfillService] bill_id=#{bill.id} external_id=#{bill.external_id} " \
        "upstream lookup error: #{e.class}: #{e.message}"
      )
      nil
    end

    if matter_id
      resolved_url = begin
        @detail_url_resolver.resolve(matter_id)
      rescue => e
        @logger.warn(
          "[BaltimoreBillLinkBackfillService] bill_id=#{bill.id} external_id=#{bill.external_id} " \
          "detail URL resolver error: #{e.class}: #{e.message}"
        )
        nil
      end

      if resolved_url.present?
        begin
          bill.update!(link: resolved_url)
          stats[:resolved] += 1
          return
        rescue ActiveRecord::RecordInvalid => e
          if e.record.errors[:link].any? { |msg| msg.include?("taken") }
            @logger.warn(
              "[BaltimoreBillLinkBackfillService] bill_id=#{bill.id} external_id=#{bill.external_id} " \
              "URL collision on #{resolved_url} — clearing to nil"
            )
            bill.update!(link: nil)
            stats[:cleared] += 1
            stats[:cleared_to_nil] += 1
            return
          else
            raise
          end
        end
      end
    end

    bill.update!(link: nil)
    stats[:cleared] += 1
    stats[:cleared_to_nil] += 1
  end

  def find_matter_id(bill)
    cached = Legislation::BillMetadata.matter_id(bill.external_id, sway_locale: "baltimore")
    if cached.nil? && bill.sway_locale.present?
      cached = Legislation::BillMetadata.matter_id(bill.external_id, sway_locale: bill.sway_locale.name)
    end
    return cached if cached.is_a?(Integer) && cached.positive?

    external_id = bill.external_id.to_s.strip
    return nil unless external_id.match?(/\A[A-Za-z0-9-]+\z/)

    matters = @client.matters(filter: "MatterFile eq '#{external_id}'")
    rows = matters.is_a?(Array) ? matters : []
    row = rows.first
    matter_id = row.is_a?(Hash) ? row["MatterId"] : nil
    (matter_id.is_a?(Integer) && matter_id.positive?) ? matter_id : nil
  end
end
