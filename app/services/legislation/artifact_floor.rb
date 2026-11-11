# frozen_string_literal: true

module Legislation
  # @lat: [[legislation-artifact-backup#Why a run checks what it found against a floor taken from the database]]
  module ArtifactFloor
    def self.bills_text_floor
      ::Bill.where.not(extracted_text: nil).where.not(extracted_text: "").count
    end
  end
end
