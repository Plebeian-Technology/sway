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

  attr_reader :items, :next_cursor

  def self.term_start_on(sway_locale)
    TermWindow.convening_date(sway_locale, TermWindow.cycle_start_year(sway_locale, Date.current))
  end

  def initialize(user:, cursor: nil, per_page: DEFAULT_PER_PAGE)
    @user = user
    @cursor = cursor
    @per_page = per_page
    @items, @next_cursor = paginate(build_items)
  end

  private

  def build_items
    items = [user_joined_item]
    reps_item = representatives_found_item
    items << reps_item if reps_item
    items.concat(legislative_term_began_items)

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

  def representatives_found_item
    active_user_legislators = @user.user_legislators.where(active: true).includes(:legislator).order(:created_at, :id).to_a
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

  def legislative_term_began_items
    @user.sway_locales.select(&:declared?).map do |locale|
      occurred_at = self.class.term_start_on(locale).in_time_zone("UTC").beginning_of_day
      Item.new(
        kind: "legislative_term_began",
        key: "legislative_term_began:#{locale.id}",
        occurred_at:,
        sway_locale: locale
      )
    end
  end

  def paginate(sorted_items)
    filtered = filter_after_cursor(sorted_items)
    window = filtered.first(@per_page + 1)
    page_items = window.first(@per_page)
    next_cursor = (window.size > @per_page) ? encode_cursor(page_items.last) : nil
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
    return nil if cursor.blank?

    sec, nsec, key = JSON.parse(Base64.urlsafe_decode64(cursor))
    [Time.at(sec, nsec, :nanosecond, in: "UTC"), key]
  end
end
