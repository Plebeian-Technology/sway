# frozen_string_literal: true

# @lat: [[embeddable-bill-widget#Embeddable bill widget#Alba serialization]]
class EmbedBillResource < ApplicationResource
  attributes :id, :title

  attribute :identifier do |bill|
    bill.external_id.presence || "Bill ##{bill.id}"
  end

  attribute :brief_summary do |bill|
    summary = bill.summary.to_s.strip
    first_chunk = summary.split(/\n\s*\n/).first || ""
    first_chunk.gsub(/\s+/, " ").strip.truncate(250)
  end

  attribute :sway_locale do |bill|
    locale = bill.sway_locale
    {
      name: locale.name,
      jurisdiction: locale.congress? ? "U.S. Congress" : locale.human_name,
      state: locale.region_name
    }
  end

  attribute :current_status do |bill|
    bill.status.presence || "Introduced"
  end

  attribute :pro_count do |bill|
    bill.bill_score&.for || 0
  end

  attribute :con_count do |bill|
    bill.bill_score&.against || 0
  end

  attribute :total_votes do |bill|
    bs = bill.bill_score
    bs ? (bs.for + bs.against) : 0
  end

  attribute :cta_url do |bill|
    query_params = {}
    raw_params = params.is_a?(Hash) ? (params[:request_params] || params) : params
    hash_params = if raw_params.is_a?(Hash)
      raw_params
    elsif raw_params.respond_to?(:to_unsafe_h)
      # steep:ignore:start
      raw_params.to_unsafe_h
      # steep:ignore:end
    else
      {}
    end

    hash_params.each do |k, v|
      key_str = k.to_s
      if key_str == "partner" || key_str == "ref" || key_str.start_with?("utm_")
        query_params[key_str] = v.to_s if v.present?
      end
    end

    base_path = "/bills/#{bill.id}"
    query_params.any? ? "#{base_path}?#{query_params.to_query}" : base_path
  end
end
