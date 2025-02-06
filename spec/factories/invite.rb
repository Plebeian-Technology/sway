# typed: true

# == Schema Information
#
# Table name: invites
#
#  id         :integer          not null, primary key
#  inviter_id :integer          not null
#  invitee_id :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

FactoryBot.define do
  factory :invite do
    inviter { build(:user) }
    invitee { build(:user) }

    initialize_with { new({inviter: build(:user), invitee: build(:user)}) }
  end
end
