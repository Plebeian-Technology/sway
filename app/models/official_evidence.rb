# frozen_string_literal: true

# @lat: [[official-service-evidence#A retained fact proves one interval]]
# == Schema Information
#
# Table name: official_evidence
# Database name: primary
#
#  id                 :integer          not null, primary key
#  date_precision     :string
#  date_semantics     :json             not null
#  fact_presence      :string           default("present"), not null
#  fact_type          :string           not null
#  jurisdiction       :string           not null
#  parsed_values      :json             not null
#  payload            :text             not null
#  payload_hash       :string(64)       not null
#  publisher          :string           not null
#  retrieved_at       :datetime         not null
#  source_url         :text             not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  external_record_id :string
#  sway_locale_id     :integer
#
# Indexes
#
#  index_official_evidence_on_hash_and_source             (payload_hash,source_url) UNIQUE
#  index_official_evidence_on_jurisdiction_and_retrieved  (jurisdiction,retrieved_at)
#  index_official_evidence_on_record_and_jurisdiction     (external_record_id,jurisdiction)
#  index_official_evidence_on_sway_locale_id              (sway_locale_id)
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
class OfficialEvidence < ApplicationRecord
  self.table_name = "official_evidence"

  module DatePrecision
    EXACT = "exact"
    YEAR_ONLY = "year_only"
    MONTH_YEAR = "month_year"
    NONE = "none"
    ALL = [EXACT, YEAR_ONLY, MONTH_YEAR, NONE].freeze
  end

  module FactPresence
    PRESENT = "present"
    ABSENT = "absent"
    PARTIAL = "partial"
    VACANT = "vacant"
    ALL = [PRESENT, ABSENT, PARTIAL, VACANT].freeze
  end

  belongs_to :sway_locale, optional: true

  validates :publisher, :jurisdiction, :source_url, :retrieved_at, :payload,
    :payload_hash, :fact_type, :fact_presence, presence: true
  validates :payload_hash, format: {with: /\A[a-f0-9]{64}\z/}
  validates :payload_hash, uniqueness: {scope: :source_url}
  validates :date_precision, inclusion: {in: DatePrecision::ALL}, allow_nil: true
  validates :fact_presence, inclusion: {in: FactPresence::ALL}
  validate :payload_hash_matches_payload

  before_validation :compute_payload_hash, if: -> { payload.present? && payload_hash.blank? }
  before_update :prevent_mutation!
  before_destroy :prevent_mutation!

  def update_columns(_attributes)
    raise ActiveRecord::ReadOnlyRecord, "OfficialEvidence records are immutable once persisted."
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "OfficialEvidence records are immutable once persisted."
  end

  private

  def payload_hash_matches_payload
    return if payload.blank? || payload_hash.blank?
    return if payload_hash == Digest::SHA256.hexdigest(payload.to_s)

    errors.add(:payload_hash, "payload_hash does not match payload SHA-256 digest")
  end

  def compute_payload_hash
    self.payload_hash = Digest::SHA256.hexdigest(payload.to_s)
  end

  def prevent_mutation!
    raise ActiveRecord::ReadOnlyRecord, "OfficialEvidence records are immutable once persisted."
  end
end
