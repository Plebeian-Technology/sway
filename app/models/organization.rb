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

  include MirrorsExternalAsset

  mirrors_external_asset(attachment_name: "icon", url_column: "icon_url")

  has_many :user_organization_memberships,
    inverse_of: :organization,
    dependent: :destroy
  has_many :organization_bill_positions,
    inverse_of: :organization,
    dependent: :destroy
  has_many :bills, through: :organization_bill_positions
  has_many :organization_follows, dependent: :destroy
  has_many :followers, through: :organization_follows, source: :user
  has_many :article_bills, dependent: :destroy

  validates :name, uniqueness: {scope: :sway_locale_id, allow_nil: true}

  # @lat: [[organizations-controller-notes#What PUBLIC_FIELDS is, and the rule around it]]
  PUBLIC_FIELDS = %i[id name icon_url sway_locale_id created_at].freeze

  # @lat: [[organization-follower-set-queries#follower_counts_for: batching the same query across a list]]
  def to_public_json
    initial = {} #: Hash[Symbol, untyped]
    payload = PUBLIC_FIELDS.each_with_object(initial) do |field, hash|
      case field
      when :icon_url
        # @lat: [[organizations-controller-notes#Why icon URL provenance rules exist]]
        hash[:icon_url] = mirrored_icon_url
      else
        hash[field] = public_send(field) if respond_to?(field)
      end
    end
    payload[:sway_locale_slug] = sway_locale&.city if respond_to?(:sway_locale)
    payload
  end

  # @lat: [[bill-session-archiving#Bill session archiving#Active views]]
  def positions
    organization_bill_positions.joins(:bill)
  end

  # @lat: [[organizations-controller-notes#Why icon URL provenance rules exist]]
  def to_simple_builder
    Jbuilder.new do |o|
      o.id id
      o.sway_locale_id sway_locale_id
      o.name name
      o.icon_url mirrored_icon_url
    end
  end

  def to_builder
    Jbuilder.new do |o|
      o.id id
      o.sway_locale_id sway_locale_id
      o.name name
      o.icon_url mirrored_icon_url

      loaded_positions =
        if organization_bill_positions.loaded? && organization_bill_positions.all? { |p| p.association(:bill).loaded? }
          organization_bill_positions.select { |p| p.persisted? && p.active? && p.bill.present? && p.bill.archived_at.nil? }
        else
          positions.where(active: true)
        end
      o.positions loaded_positions.map(&:to_sway_json)
    end
  end

  def mirrored_icon_url
    MirroredAssetUrl.for(icon, fallback: icon_url)
  end

  # @lat: [[organization-follower-set-queries#follower_set: the one raw-SQL UNION in the codebase]]
  def follower_set
    sql = <<~SQL
      SELECT user_id FROM user_organization_memberships
        WHERE organization_id = ? AND status = 'active'
      UNION
      SELECT user_id FROM organization_follows
        WHERE organization_id = ?
    SQL
    self.class.connection.execute(
      self.class.sanitize_sql_array([sql, id, id])
    ).map { |row| (row["user_id"] || row.values.first).to_i }
  end

  # @lat: [[organization-follower-set-queries#notifiable_follower_set_for: the notify set across two sub-populations]]
  def notifiable_follower_set_for(change_types)
    follow_rows = organization_follows.select(
      :user_id, :notification_cadence,
      :notify_on_new_position, :notify_on_support_change, :notify_on_summary_change
    )

    follow_tuples = [] #: Array[[Integer, String]]
    follow_user_ids = [] #: Array[Integer]

    follow_rows.each do |follow|
      follow_user_ids << follow.user_id
      next if change_types.all? { |ct| follow.muted_for?(ct) }

      follow_tuples << [follow.user_id, follow.notification_cadence]
    end

    member_user_ids = user_organization_memberships
      .where(status: :active)
      .where.not(user_id: follow_user_ids)
      .pluck(:user_id)

    member_tuples = [] #: Array[[Integer, String]]

    unless member_user_ids.empty?
      User.where(id: member_user_ids).pluck(
        :id,
        :org_position_cadence_default,
        :notify_on_new_position_default,
        :notify_on_support_change_default,
        :notify_on_summary_change_default
      ).each do |uid, cadence, on_new, on_support, on_summary|
        enabled = change_types.any? do |ct|
          case ct
          when :new_position then on_new
          when :support_change then on_support
          when :summary_change then on_summary
          else false
          end
        end
        next unless enabled

        member_tuples << [uid, cadence]
      end
    end

    follow_tuples + member_tuples
  end
end
