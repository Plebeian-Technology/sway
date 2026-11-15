# frozen_string_literal: true

require "base64"
require "json"

# @lat: [[home-feed#What items a user sees and how paging works]]
class FeedQuery
  DEFAULT_PER_PAGE = 20

  class Item < Data.define(
    :kind,
    :key,
    :occurred_at,
    :sway_locale,
    :bill,
    :legislator,
    :legislators,
    :organization_bill_position,
    :user_vote,
    :legislator_vote
  )
    def initialize(
      kind:,
      key:,
      occurred_at:,
      sway_locale: nil,
      bill: nil,
      legislator: nil,
      legislators: nil,
      organization_bill_position: nil,
      user_vote: nil,
      legislator_vote: nil
    )
      super
    end
  end

  def self.term_start_on(sway_locale)
    TermWindow.convening_date(sway_locale, TermWindow.cycle_start_year(sway_locale, Date.current))
  end

  def initialize(user:, cursor: nil, per_page: DEFAULT_PER_PAGE, query: nil)
    @user = user
    @cursor = cursor
    @per_page = per_page
    @query = query&.strip&.downcase.presence
  end

  def items
    page_result[0]
  end

  def next_cursor
    page_result[1]
  end

  def match_count
    matching_items.size
  end

  private

  def matching_items
    @matching_items ||= filter_by_query(build_items)
  end

  def page_result
    @page_result ||= paginate(matching_items)
  end

  def build_items
    items = [user_joined_item]
    reps_item = representatives_found_item
    items << reps_item if reps_item
    items.concat(legislative_term_began_items)
    items.concat(bill_of_the_month_released_items)
    items.concat(legislator_voted_items)
    items.concat(organization_position_taken_items)

    items.sort do |a, b|
      cmp = b.occurred_at <=> a.occurred_at
      cmp.zero? ? b.key <=> a.key : cmp
    end
  end

  def user_joined_item
    Item.new(
      kind: "user_joined",
      key: "user_joined:#{@user.id}",
      occurred_at: @user.created_at
    )
  end

  def active_user_legislators
    @active_user_legislators ||= @user
      .user_legislators
      .where(active: true)
      .includes(legislator: [:district, {active_term: %i[seat district]}, {photo_attachment: :blob}])
      .order(:created_at, :id)
      .to_a
  end

  def representatives_found_item
    return nil if active_user_legislators.empty?

    earliest_created_at = active_user_legislators.first&.created_at
    return nil unless earliest_created_at
    Item.new(
      kind: "representatives_found",
      key: "representatives_found:#{@user.id}",
      occurred_at: earliest_created_at,
      legislators: active_user_legislators.map(&:legislator)
    )
  end

  def declared_locales
    @declared_locales ||= @user.sway_locales.select(&:declared?)
  end

  def term_starts_by_locale_id
    @term_starts_by_locale_id ||= declared_locales.each_with_object({}) do |locale, map|
      map[locale.id] = self.class.term_start_on(locale)
    end
  end

  def legislative_term_began_items
    declared_locales.map do |locale|
      occurred_at = term_starts_by_locale_id.fetch(locale.id).in_time_zone("UTC").beginning_of_day
      Item.new(
        kind: "legislative_term_began",
        key: "legislative_term_began:#{locale.id}",
        occurred_at:,
        sway_locale: locale
      )
    end
  end

  def bill_of_the_month_released_items
    return [] if declared_locales.empty?

    today_utc = Time.now.utc.to_date
    candidates = Bill
      .where(sway_locale_id: declared_locales.map(&:id))
      .where.not(scheduled_release_date_utc: nil)
      .where(scheduled_release_date_utc: ..today_utc)
      .includes(:sway_locale, :legislative_session)
      .to_a

    matching_bills = candidates.select do |bill|
      term_start = term_starts_by_locale_id.fetch(bill.sway_locale_id)
      release_date = bill.scheduled_release_date_utc
      release_date && release_date >= term_start && bill_in_current_term?(bill, term_start)
    end
    return [] if matching_bills.empty?

    votes_by_bill_id = @user.user_votes.where(bill_id: matching_bills.map(&:id)).index_by(&:bill_id)
    matching_bills.filter_map do |bill|
      release_date = bill.scheduled_release_date_utc
      next unless release_date

      Item.new(
        kind: "bill_of_the_month_released",
        key: "bill_of_the_month_released:#{bill.id}",
        occurred_at: release_date.in_time_zone("UTC").beginning_of_day,
        sway_locale: bill.sway_locale,
        bill:,
        user_vote: votes_by_bill_id[bill.id]
      )
    end
  end

  def legislator_voted_items
    return [] if active_user_legislators.empty? || declared_locales.empty?

    legislators_by_id = active_user_legislators.map(&:legislator).index_by(&:id)
    votes = LegislatorVote.where(legislator_id: legislators_by_id.keys, inferred: false).to_a
    return [] if votes.empty?

    bills_by_id = Bill
      .unscope(where: :archived_at)
      .where(id: votes.map(&:bill_id).uniq, sway_locale_id: declared_locales.map(&:id))
      .includes(:sway_locale, :legislative_session)
      .index_by(&:id)
    return [] if bills_by_id.empty?

    user_votes_by_bill_id = @user.user_votes.where(bill_id: bills_by_id.keys).index_by(&:bill_id)
    votes.filter_map do |legislator_vote|
      bill = bills_by_id[legislator_vote.bill_id]
      legislator = legislators_by_id[legislator_vote.legislator_id]
      next unless bill && legislator

      term_start_date = term_starts_by_locale_id.fetch(bill.sway_locale_id)
      occurred_at = legislator_vote_occurred_at(bill, legislator, legislator_vote)
      term_start = term_start_date.in_time_zone("UTC").beginning_of_day
      next if occurred_at < term_start
      next unless bill_in_current_term?(bill, term_start_date)

      Item.new(
        kind: "legislator_voted",
        key: "legislator_voted:#{legislator_vote.id}",
        occurred_at:,
        sway_locale: bill.sway_locale,
        bill:,
        legislator:,
        legislator_vote:,
        user_vote: user_votes_by_bill_id[bill.id]
      )
    end
  end

  def legislator_vote_occurred_at(bill, legislator, legislator_vote)
    if senator?(legislator)
      bill.senate_vote_date_time_utc || bill.house_vote_date_time_utc || legislator_vote.created_at
    else
      bill.house_vote_date_time_utc || bill.senate_vote_date_time_utc || legislator_vote.created_at
    end
  end

  def senator?(legislator)
    chamber = legislator.active_term&.seat&.chamber
    return true if chamber&.casecmp?("senate")

    legislator.title.to_s.match?(/\bsen/i)
  end

  def organization_position_taken_items
    return [] if declared_locales.empty?

    followed_organization_ids = @user.followed_organizations.pluck(:id)
    return [] if followed_organization_ids.empty?

    positions = OrganizationBillPosition
      .where(organization_id: followed_organization_ids, active: true)
      .where.not(activated_at: nil)
      .includes(:organization)
      .to_a
    return [] if positions.empty?

    bills_by_id = Bill
      .unscope(where: :archived_at)
      .where(id: positions.map(&:bill_id).uniq, sway_locale_id: declared_locales.map(&:id))
      .includes(:sway_locale, :legislative_session)
      .index_by(&:id)
    return [] if bills_by_id.empty?

    user_votes_by_bill_id = @user.user_votes.where(bill_id: bills_by_id.keys).index_by(&:bill_id)
    positions.filter_map do |position|
      bill = bills_by_id[position.bill_id]
      activated_at = position.activated_at
      next unless bill && activated_at

      term_start_date = term_starts_by_locale_id.fetch(bill.sway_locale_id)
      term_start = term_start_date.in_time_zone("UTC").beginning_of_day
      next if activated_at < term_start
      next unless bill_in_current_term?(bill, term_start_date)

      Item.new(
        kind: "organization_position_taken",
        key: "organization_position_taken:#{position.id}",
        occurred_at: activated_at,
        sway_locale: bill.sway_locale,
        bill:,
        organization_bill_position: position,
        user_vote: user_votes_by_bill_id[bill.id]
      )
    end
  end

  def bill_in_current_term?(bill, term_start)
    if (session = bill.legislative_session)
      return false if session.start_date < term_start
    end

    introduced_at = bill.introduced_date_time_utc
    return false if introduced_at && introduced_at.to_time.utc.to_date < term_start

    true
  end

  def filter_by_query(items)
    query = @query
    return items unless query

    items.select { |item| item_matches_query?(item, query) }
  end

  def item_matches_query?(item, query)
    searchable_texts(item).any? { |text| text.downcase.include?(query) }
  end

  def searchable_texts(item)
    texts = [] #: Array[String?]
    if (bill = item.bill)
      texts << bill.title << bill.external_id
    end
    if (legislator = item.legislator)
      texts << legislator.full_name
    end
    item.legislators&.each { |legislator| texts << legislator.full_name }
    if (locale = item.sway_locale)
      texts << locale.human_name << locale.short_name
    end
    if (organization_name = item.organization_bill_position&.organization&.name)
      texts << organization_name
    end
    texts.compact
  end

  def paginate(sorted_items)
    filtered = filter_after_cursor(sorted_items)
    window = filtered.first(@per_page + 1)
    page_items = window.first(@per_page)
    last_page_item = page_items.last
    next_cursor = (window.size > @per_page && last_page_item) ? encode_cursor(last_page_item) : nil
    [page_items, next_cursor]
  end

  def filter_after_cursor(sorted_items)
    decoded = decode_cursor(@cursor)
    return sorted_items unless decoded

    cursor_time, cursor_key = decoded
    sorted_items.select do |item|
      item_time = item.occurred_at.to_time.utc
      item_time < cursor_time || (item_time == cursor_time && item.key < cursor_key)
    end
  end

  def encode_cursor(item)
    time = item.occurred_at.to_time.utc
    Base64.urlsafe_encode64(JSON.generate([time.to_i, time.nsec, item.key]), padding: false)
  end

  def decode_cursor(cursor)
    return nil if cursor.nil? || cursor.blank?

    parsed = JSON.parse(Base64.urlsafe_decode64(cursor))
    return nil unless parsed.is_a?(Array) && parsed.size == 3

    sec, nsec, key = parsed
    return nil unless sec.is_a?(Integer) && nsec.is_a?(Integer) && key.is_a?(String)

    [Time.at(sec, nsec, :nanosecond, in: "UTC"), key]
  rescue ArgumentError, JSON::ParserError, TypeError, RangeError, EncodingError
    nil
  end
end
