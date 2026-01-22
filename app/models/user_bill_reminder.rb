# frozen_string_literal: true
# typed: true

class UserBillReminder < ApplicationRecord
  belongs_to :user
  belongs_to :bill
end
