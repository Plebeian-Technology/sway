# frozen_string_literal: true

# @lat: [[pending-org-digest-entry-design#Why PendingOrganizationDigestEntry is a durable queue]]
# == Schema Information
#
# Table name: pending_organization_digest_entries
# Database name: primary
#
#  id           :integer          not null, primary key
#  cadence      :string           not null
#  change_types :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  bill_id      :integer          not null
#  org_id       :integer          not null
#  user_id      :integer          not null
#
# Indexes
#
#  idx_pending_org_digest_on_cadence_created_at          (cadence,created_at)
#  index_pending_organization_digest_entries_on_user_id  (user_id)
#
class PendingOrganizationDigestEntry < ApplicationRecord
  self.table_name = "pending_organization_digest_entries"
  belongs_to :user

  # @lat: [[pending-org-digest-entry-design#Why PendingOrganizationDigestEntry is a durable queue]]
  CADENCES = %w[daily weekly].freeze

  validates :cadence, inclusion: {in: CADENCES}
  validates :change_types, :org_id, :bill_id, presence: true
end
