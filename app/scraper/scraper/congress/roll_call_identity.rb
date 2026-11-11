# frozen_string_literal: true

module Scraper
  module Congress
    # @lat: [[roll-call-identity]]
    class RollCallIdentity
      # @lat: [[roll-call-identity#Identifying a congressional roll call#Why the record is checked rather than trusted]]
      TIME_ZONES = ["UTC", "America/New_York"].freeze

      attr_reader :document_name, :question, :title, :voted_on

      # @lat: [[congress-roll-calls#Why a fetched record has to name the bill's own vote]]
      def initialize(document_name:, question:, voted_on:, title: nil)
        @document_name = document_name.presence&.strip
        @question = question.presence&.strip
        @title = title.presence&.strip
        @voted_on = voted_on
      end

      # @lat: [[roll-call-identity#How RollCallIdentity normalizes and compares bill numbers]]
      def self.normalize(value)
        value.to_s.downcase.gsub(/[^a-z0-9]/, "")
      end

      # @lat: [[roll-call-identity#How RollCallIdentity normalizes and compares bill numbers]]
      def names?(external_id)
        return false if document_name.blank? || external_id.blank?

        self.class.normalize(document_name) == self.class.normalize(external_id)
      end

      # @lat: [[roll-call-identity#Identifying a congressional roll call#Why the record is checked rather than trusted]]
      def taken_on?(time)
        return false if voted_on.nil? || time.nil?

        TIME_ZONES.any? { |zone| voted_on == time.in_time_zone(zone).to_date }
      end

      def to_h
        {document_name: document_name, question: question, title: title, voted_on: voted_on&.iso8601}
      end
    end
  end
end
