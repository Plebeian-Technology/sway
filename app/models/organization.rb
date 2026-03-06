# frozen_string_literal: true

# == Schema Information
#
# Table name: organizations
# Database name: primary
#
#  id             :integer          not null, primary key
#  icon_url       :string
#  name           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_organizations_on_name_and_sway_locale_id  (name,sway_locale_id) UNIQUE
#  index_organizations_on_sway_locale_id           (sway_locale_id)
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
class Organization < ApplicationRecord
  belongs_to :sway_locale
  has_one_attached :icon

  after_commit :enqueue_icon_mirroring, if: :saved_change_to_icon_url?

  has_many :user_organization_memberships,
           inverse_of: :organization,
           dependent: :destroy
  has_many :organization_bill_positions,
           inverse_of: :organization,
           dependent: :destroy
  has_many :bills, through: :organization_bill_positions

  validates :name, uniqueness: { scope: :sway_locale_id, allow_nil: true }

  def members
    user_organization_memberships
  end

  def positions
    organization_bill_positions
  end

  def to_simple_builder
    Jbuilder.new do |o|
      o.id id
      o.sway_locale_id sway_locale_id
      o.name name
      o.icon_url icon_url
    end
  end

  def to_builder
    Jbuilder.new do |o|
      o.id id
      o.sway_locale_id sway_locale_id
      o.name name
      o.icon_url icon_url

      o.positions positions.map(&:to_sway_json)
    end
  end

  private

  def enqueue_icon_mirroring
    return if id.blank?
    return if internal_asset_url?(icon_url)

    MirrorExternalAssetJob.perform_later(
      record_class_name: self.class.name,
      record_id: id,
      attachment_name: "icon",
      url_column: "icon_url",
    )
  end

  def internal_asset_url?(url)
    return true if url.blank?

    uri = URI.parse(url)
    return false unless uri.is_a?(URI::HTTP)

    host = uri.host.to_s.downcase
    host.ends_with?("sway.vote") ||
      (
        host == "storage.googleapis.com" &&
          uri.path.to_s.start_with?("/sway-assets/")
      )
  rescue URI::InvalidURIError
    false
  end
end
