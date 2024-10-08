# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: user_districts
#
#  id          :integer          not null, primary key
#  district_id :integer          not null
#  user_id     :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class UserDistrict < ApplicationRecord
  belongs_to :district
  belongs_to :user
end
