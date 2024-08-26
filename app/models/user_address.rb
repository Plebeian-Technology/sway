# frozen_string_literal: true

# == Schema Information
#
# Table name: user_addresses
#
#  id         :integer          not null, primary key
#  address_id :integer          not null
#  user_id    :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class UserAddress < ApplicationRecord
  belongs_to :address
  belongs_to :user
end
