# frozen_string_literal: true

class BillSponsor < ApplicationRecord
  belongs_to :legislator
  belongs_to :bill
end
