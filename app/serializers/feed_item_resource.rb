# frozen_string_literal: true

class FeedItemResource < ApplicationResource
  ORGANIZATION_SUPPORT_LABELS = {
    "FOR" => "Support",
    "AGAINST" => "Oppose",
    "ABSTAIN" => "Neutral"
  }.freeze

  attributes :key, :kind

  attribute :occurred_at do |item|
    item.occurred_at.iso8601
  end

  attribute :sway_locale do |item|
    locale = item.sway_locale
    next nil unless locale

    {
      id: locale.id,
      name: FeedItemResource.short_locale_name(locale)
    }
  end

  attribute :bill do |item|
    bill = item.bill
    next nil unless bill

    vote_counts = params[:vote_counts_by_bill_id] || {}
    share_counts = params[:share_counts_by_bill_id] || {}

    {
      id: bill.id,
      external_id: bill.external_id,
      title: bill.title,
      summary: bill.summary,
      vote_count: vote_counts.fetch(bill.id, 0),
      share_count: share_counts.fetch(bill.id, 0)
    }
  end

  attribute :legislator do |item|
    FeedItemResource.serialize_legislator(item.legislator)
  end

  attribute :legislators do |item|
    (item.legislators || []).filter_map { |legislator| FeedItemResource.serialize_legislator(legislator) }
  end

  attribute :organization do |item|
    position = item.organization_bill_position
    org = position&.organization
    next nil unless position && org

    {
      id: org.id,
      name: org.name,
      support: ORGANIZATION_SUPPORT_LABELS.fetch(position.support, position.support)
    }
  end

  attribute :user_support do |item|
    item.user_vote&.support
  end

  attribute :legislator_support do |item|
    item.legislator_vote&.support
  end

  attribute :agreement do |item|
    user_support = item.user_vote&.support
    legislator_support = item.legislator_vote&.support
    next nil if user_support.blank? || legislator_support.blank?
    next nil if user_support == "ABSTAIN" || legislator_support == "ABSTAIN"

    (user_support == legislator_support) ? "agree" : "differ"
  end

  def self.short_locale_name(locale)
    if locale.congress?
      "U.S. Congress"
    elsif locale.regional?
      locale.region_name.titleize.tr("_", " ")
    else
      locale.city_name.titleize.tr("_", " ")
    end
  end

  def self.serialize_legislator(legislator)
    return nil unless legislator

    {
      id: legislator.id,
      full_name: legislator.full_name,
      title: legislator.title,
      district_name: legislator.district&.name,
      photo_url: MirroredAssetUrl.for(legislator.photo, fallback: legislator.photo_url)
    }
  end
end
