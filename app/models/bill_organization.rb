# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: bill_organizations
#
#  id             :integer          not null, primary key
#  icon_path      :string
#  name           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_bill_organizations_on_name_and_sway_locale_id  (name,sway_locale_id) UNIQUE
#  index_bill_organizations_on_sway_locale_id           (sway_locale_id)
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
class BillOrganization < ApplicationRecord
  extend T::Sig
  include SwayGoogleCloudStorage

  belongs_to :sway_locale

  has_many :organization_bill_positions, inverse_of: :organization, dependent: :destroy
  has_many :bills, through: :organization_bill_positions

  validates :name, uniqueness: {scope: :sway_locale_id, allow_nil: true}

  def positions
    organization_bill_positions
  end

  sig { params(current_icon_path: T.nilable(String)).void }
  def remove_icon(current_icon_path)
    return if current_icon_path.blank?
    return unless icon_path != current_icon_path

    delete_file(bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS], file_name: current_icon_path)
  end

  sig { returns(Jbuilder) }
  def to_simple_builder
    Jbuilder.new do |o|
      o.id id
      o.sway_locale_id sway_locale_id
      o.name name
      o.icon_path icon_path
    end
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |o|
      o.id id
      o.sway_locale_id sway_locale_id
      o.name name
      o.icon_path icon_path

      o.positions positions.map(&:to_sway_json)
    end
  end
end
