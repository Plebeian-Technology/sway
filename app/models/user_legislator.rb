# typed: strict

# == Schema Information
#
# Table name: user_legislators
#
#  id            :integer          not null, primary key
#  legislator_id :integer          not null
#  user_id       :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class UserLegislator < ApplicationRecord
  extend T::Sig

  belongs_to :legislator
  belongs_to :user
end
