# frozen_string_literal: true
# typed: strict

class BillSponsor < ApplicationRecord
    belongs_to :legislator
    belongs_to :bill
end
