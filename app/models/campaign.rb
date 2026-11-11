# frozen_string_literal: true

# == Schema Information
#
# Table name: campaigns
# Database name: primary
#
#  id                         :integer          not null, primary key
#  active                     :boolean          default(FALSE), not null
#  ai_summary                 :text
#  icon_url                   :string
#  letter_count               :integer
#  name                       :string
#  organization_link_decision :string
#  sender_count               :integer
#  source_campaign_draft_hash :string
#  summary                    :text             not null
#  support                    :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  bill_id                    :integer          not null
#  organization_id            :integer
#
# Indexes
#
#  index_campaigns_on_bill_and_name               (bill_id,name) UNIQUE WHERE name IS NOT NULL
#  index_campaigns_on_bill_id                     (bill_id)
#  index_campaigns_on_organization_id             (organization_id)
#  index_campaigns_on_organization_link_decision  (organization_link_decision)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id)
#  organization_id  (organization_id => organizations.id)
#
class Campaign < ApplicationRecord
  # @lat: [[campaign-scope-and-identity#Why the name bound sits on the model]]
  MAX_NAME_CHARS = 500

  # @lat: [[campaign-scope-and-identity#Why the stance map is a copy]]
  STANCE_TO_SUPPORT = {
    "support" => "FOR",
    "oppose" => "AGAINST",
    "neutral" => "ABSTAIN",
    "FOR" => "FOR",
    "AGAINST" => "AGAINST",
    "ABSTAIN" => "ABSTAIN"
  }.freeze

  def self.normalize_support(value)
    STANCE_TO_SUPPORT[value.to_s]
  end

  # @lat: [[campaign-organization-link#Why there are four states and not two]]
  LINKED = "linked"
  NO_ORGANIZATION = "none"
  UNDETERMINED = "undetermined"
  ORGANIZATION_LINK_DECISIONS = [LINKED, NO_ORGANIZATION, UNDETERMINED].freeze

  # @lat: [[campaign-scope-and-identity#What the bill prop carries about campaigns]]
  belongs_to :bill
  belongs_to :organization, optional: true

  has_one :sway_locale, through: :bill

  # @lat: [[campaign-scope-and-identity#How one campaign is told from another]]
  validates :name, uniqueness: {scope: :bill_id, allow_nil: true},
    length: {maximum: MAX_NAME_CHARS}, allow_nil: true

  validates :support, :summary, presence: {message: "can't be blank"}

  validates :organization_link_decision, inclusion: {in: ORGANIZATION_LINK_DECISIONS}, allow_nil: true

  # @lat: [[campaign-organization-link#Why an organization from another locale is refused]]
  validate :organization_matches_link_decision

  # @lat: [[campaign-scope-and-identity#Where the wrong scope came from]]

  private

  def organization_matches_link_decision
    if organization_link_decision == LINKED && organization_id.nil?
      errors.add(:organization, "must be set when the decision is #{LINKED}")
    elsif organization_link_decision != LINKED && organization_id.present?
      errors.add(:organization, "must be absent unless the decision is #{LINKED}")
    end
  end
end
