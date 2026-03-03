# frozen_string_literal: true

# == Schema Information
#
# Table name: invites
# Database name: primary
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  invitee_id :integer          not null
#  inviter_id :integer          not null
#
# Indexes
#
#  index_invites_on_invitee_id                 (invitee_id)
#  index_invites_on_inviter_id                 (inviter_id)
#  index_invites_on_inviter_id_and_inviter_id  (inviter_id) UNIQUE
#
# Foreign Keys
#
#  invitee_id  (invitee_id => users.id)
#  inviter_id  (inviter_id => users.id)
#
# Invite urls are short urls and are sent with the route /s/<unique_key>. When a new user visits the short url they are redirected to a long url with route /<user_id>/<invite_uuid>.

# When a new user visits the short url and successfully completes registration, a new Invite should be created with and inviter_id equal to the value of <user_id> from the long url. The invitee_id should be equal to the value of the new user's id.
class Invite < ApplicationRecord
  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "User"
end
