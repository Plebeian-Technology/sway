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

  # @lat: [[voter-privacy-threshold#The embed widget withholds counts on the server]]
  attribute :pro_count do |bill|
    for_count, against_count = EmbedBillResource.tally(bill)
    VoteComparisonPrivacy.withheld?(for_count, against_count) ? nil : for_count
  end

  attribute :con_count do |bill|
    for_count, against_count = EmbedBillResource.tally(bill)
    VoteComparisonPrivacy.withheld?(for_count, against_count) ? nil : against_count
  end

  attribute :pro_percent do |bill|
    EmbedBillResource.percentages(bill)&.fetch(:for)
  end

  attribute :con_percent do |bill|
    EmbedBillResource.percentages(bill)&.fetch(:against)
  end

  attribute :total_votes do |bill|
    EmbedBillResource.tally(bill).sum
  end

  attribute :comparison_suppressed do |bill|
    VoteComparisonPrivacy.withheld?(*EmbedBillResource.tally(bill))
  end

  attribute :voters_needed do |bill|
    VoteComparisonPrivacy.voters_needed(*EmbedBillResource.tally(bill))
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

  def self.tally(bill)
    score = bill.bill_score
    [score&.for || 0, score&.against || 0]
  end

  def self.percentages(bill)
    for_count, against_count = tally(bill)
    return nil if VoteComparisonPrivacy.withheld?(for_count, against_count)

    VoteComparisonPrivacy.rounded_percentages({for: for_count, against: against_count}, voters: for_count + against_count)
  end
end
