# frozen_string_literal: true

# == Schema Information
#
# Table name: legislator_identifiers
# Database name: primary
#
#  id             :integer          not null, primary key
#  source         :string           not null
#  value          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  legislator_id  :integer          not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_legislator_identifiers_on_legislator_id                (legislator_id)
#  index_legislator_identifiers_on_locale_and_source_and_value  (sway_locale_id,source,value) UNIQUE
#
# Foreign Keys
#
#  legislator_id   (legislator_id => legislators.id)
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
# @lat: [[legislator-identity-value-design#Why LegislatorIdentifier's many-to-one shape is the point]]
class LegislatorIdentifier < ApplicationRecord
  belongs_to :legislator
  belongs_to :sway_locale

  validates :source, presence: true
  validates :value, presence: true, uniqueness: {scope: [:sway_locale_id, :source]}

  validate :locale_matches_the_legislator

  class << self
    def legislator_for(sway_locale:, identity:)
      find_by(
        sway_locale_id: sway_locale.id,
        source: identity.source,
        value: identity.value
      )&.legislator
    end

    def record!(legislator:, identity:)
      find_or_create_by!(
        sway_locale_id: legislator.sway_locale_id,
        source: identity.source,
        value: identity.value
      ) { |identifier| identifier.legislator = legislator }
    end
  end

  def identity
    LegislatorIdentity.new(source: source, value: value)
  end

  private

  # @lat: [[legislator-identity-value-design#Why locale_matches_the_legislator is a validation, not a correction]]
  def locale_matches_the_legislator
    return if legislator.nil? || sway_locale_id.nil?
    return if legislator.sway_locale_id == sway_locale_id

    errors.add(
      :sway_locale_id,
      "must be the legislator's own locale (identifier says #{sway_locale_id}, " \
      "legislator #{legislator.id.inspect} is in #{legislator.sway_locale_id})"
    )
  end
end
