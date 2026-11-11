# frozen_string_literal: true

# @lat: [[bill-creator-positions-tab#Why testimony report resources expose raw counts and evidence without confidence scores]]
class TestimonyCoverageResource < ApplicationResource
  attributes :total_chars, :reached_chars, :removed_chars, :repair_added_chars, :left_out_chars,
    :total_letters, :reached_letters, :removed_letters, :left_out_letters,
    :individual_letter_count, :model_fallback_letter_count, :repeat_letter_count,
    :attachment_cut_count, :attachment_cut_cap,
    :paste_present, :paste_chars, :paste_share_of_limit, :displaced_letter_count,
    :digest, :acknowledged

  attribute :state do |result|
    result.state.to_s
  end

  attribute :coverage_gap do |result|
    Testimony::CoverageReport.coverage_gap?(result)
  end

  attribute :acknowledged_by_email do |result|
    result.acknowledged_by_email
  end

  attribute :acknowledged_at do |result|
    result.acknowledged_at&.iso8601
  end
end
