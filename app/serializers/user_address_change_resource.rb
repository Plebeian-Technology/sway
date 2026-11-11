# frozen_string_literal: true

class UserAddressChangeResource < ApplicationResource
  attributes :id,
    :user_id,
    :previous_address_id,
    :new_address_id,
    :deactivated_legislator_ids,
    :activated_legislator_ids,
    :deactivated_district_ids,
    :activated_district_ids,
    :previous_sway_locale_ids,
    :new_sway_locale_ids,
    :prior_vote_count,
    :prior_voted_bill_ids,
    :prior_voted_sway_locale_ids

  attribute :previous_sway_locale_names do |record|
    locale_names_for(record.previous_sway_locale_ids)
  end

  attribute :new_sway_locale_names do |record|
    locale_names_for(record.new_sway_locale_ids)
  end

  attribute :cross_district do |record|
    record.cross_district?
  end

  attribute :cross_sway_locale do |record|
    record.cross_sway_locale?
  end

  attribute :voted_before_switch do |record|
    record.voted_before_switch?
  end

  attribute :user_switch_count do |record|
    counts = params[:switch_counts_by_user_id]
    if counts.is_a?(Hash)
      counts.fetch(record.user_id, 1)
    else
      UserAddressChange.where(user_id: record.user_id).count
    end
  end

  attribute :created_at do |record|
    record.created_at&.iso8601
  end

  private

  def locale_names_for(locale_ids)
    ids = Array(locale_ids)
    return [] if ids.empty?

    names_by_id = params[:locale_names_by_id]
    if names_by_id.is_a?(Hash)
      ids.filter_map { |id| names_by_id[id] }
    else
      by_id = SwayLocale.where(id: ids).to_h { |locale| [locale.id, locale.name] }
      ids.filter_map { |id| by_id[id] }
    end
  end
end
