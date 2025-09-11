# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: user_organization_memberships
#
#  id              :integer          not null, primary key
#  role            :integer          not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :integer          not null
#  user_id         :integer          not null
#
# Indexes
#
#  idx_on_user_id_organization_id_7cc0c85071               (user_id,organization_id) UNIQUE
#  index_user_organization_memberships_on_organization_id  (organization_id)
#  index_user_organization_memberships_on_user_id          (user_id)
#
# Foreign Keys
#
#  organization_id  (organization_id => organizations.id)
#  user_id          (user_id => users.id)
#
class UserOrganizationMembership < ApplicationRecord
  extend T::Sig

  belongs_to :user
  belongs_to :organization

  enum :role, { standard: 0, admin: 1 }, default: :standard

  validates :role, presence: true

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |m|
      m.id id
      m.user_id T.unsafe(self).user.id
      m.organization T.unsafe(self).organization.to_simple_builder.attributes!
      m.role T.unsafe(self).admin? ? "admin" : "standard"
    end
  end
end
