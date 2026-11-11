# frozen_string_literal: true

# == Schema Information
#
# Table name: legislative_sessions
# Database name: primary
#
#  id             :integer          not null, primary key
#  active         :boolean          default(FALSE), not null
#  end_date       :date             not null
#  name           :string           not null
#  start_date     :date             not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_legislative_sessions_on_sway_locale_id_and_active  (sway_locale_id,active)
#  index_legislative_sessions_on_sway_locale_id_and_name    (sway_locale_id,name) UNIQUE
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
# @lat: [[locale-extension#Legislative session schema and validations]]
class LegislativeSession < ApplicationRecord
  belongs_to :sway_locale

  has_many :legislator_terms, ->(session) {
    overlap = LegislatorTerm.sanitize_sql_array(
      ["#{TermWindow.begins_on_sql} < ? AND #{TermWindow.ends_on_sql} > ?", session.end_date.to_s, session.start_date.to_s]
    )
    LegislatorTerm.unscope(where: :legislative_session_id)
      .joins(:district)
      .where(districts: {sway_locale_id: session.sway_locale_id})
      .where(Arel.sql(overlap))
  }, foreign_key: :legislative_session_id, inverse_of: false

  has_many :legislators, -> { Legislator.distinct }, through: :legislator_terms
  has_many :bills, dependent: :nullify

  scope :containing_date, ->(date) {
    target = date.respond_to?(:to_date) ? date.to_date : date
    where("start_date <= ? AND end_date >= ?", target, target)
  }

  scope :active, -> { where(active: true) }

  validates :name, presence: true, uniqueness: {scope: :sway_locale_id}
  validates :start_date, :end_date, presence: true
  validate :end_date_on_or_after_start_date

  def upstream_name
    definition&.upstream_name || name
  end

  def definition
    return nil unless sway_locale&.name

    SwayLocale::DocumentReader.find(sway_locale.name)&.legislative_sessions&.find { |s| s.name == name }
  end

  private

  def end_date_on_or_after_start_date
    return if start_date.blank? || end_date.blank?
    return if end_date >= start_date

    errors.add(:end_date, "must be on or after start date")
  end
end
