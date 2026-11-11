# frozen_string_literal: true

module Legistar
  # @lat: [[legistar-matter-status-mapping#Why Legistar names collapse onto four statuses]]
  class StatusMapper
    # @lat: [[legistar-matter-status-mapping#The Baltimore Legistar status vocabulary]]
    STATUS_MAP = {
      "adopted" => Bill::Status::PASSED,
      "enacted" => Bill::Status::PASSED,
      "signed by mayor" => Bill::Status::PASSED,
      "confirmed" => Bill::Status::PASSED,
      "confirmed after 3 meetings without council action" => Bill::Status::PASSED,
      "passed" => Bill::Status::PASSED,
      "matter concluded" => Bill::Status::PASSED,

      "failed" => Bill::Status::FAILED,
      "failed - end of term" => Bill::Status::FAILED,
      "withdrawn" => Bill::Status::FAILED,
      "rules withdrawn" => Bill::Status::FAILED,
      "filed" => Bill::Status::FAILED,

      "vetoed by mayor" => Bill::Status::VETOED,

      "in committee" => Bill::Status::COMMITTEE,
      "1st reader" => Bill::Status::COMMITTEE,
      "first reading" => Bill::Status::COMMITTEE,
      "2nd reader" => Bill::Status::COMMITTEE,
      "second reading" => Bill::Status::COMMITTEE,
      "3rd reader, final passage" => Bill::Status::COMMITTEE,
      "3rd reader, advance from 2nd on same day" => Bill::Status::COMMITTEE,
      "3rd reader, to be held one meeting" => Bill::Status::COMMITTEE,
      "3rd reader, to be held two meetings" => Bill::Status::COMMITTEE,
      "3rd reader, enrolled for final passage" => Bill::Status::COMMITTEE,
      "3rd reader, recalled from the mayor's office" => Bill::Status::COMMITTEE,
      "introduced in council" => Bill::Status::COMMITTEE,
      "introduction of rule change" => Bill::Status::COMMITTEE,
      "nominated" => Bill::Status::COMMITTEE,
      "before the mayor" => Bill::Status::COMMITTEE,
      "return from mayor's desk for further consideration requested" => Bill::Status::COMMITTEE,
      "returned from mayor's desk for further consideration" => Bill::Status::COMMITTEE,
      "new business" => Bill::Status::COMMITTEE,
      "reported to council" => Bill::Status::COMMITTEE,
      "referred" => Bill::Status::COMMITTEE,
      "public hearing" => Bill::Status::COMMITTEE,
      "worksession" => Bill::Status::COMMITTEE,
      "held" => Bill::Status::COMMITTEE,
      "agenda ready" => Bill::Status::COMMITTEE,
      "consent agenda" => Bill::Status::COMMITTEE,
      "tabled" => Bill::Status::COMMITTEE
    }.freeze

    def self.map(status_name)
      return nil unless status_name.is_a?(::String)

      cleaned = Sway::Utf8.scrub(status_name).strip.downcase
      return nil if cleaned.empty?

      mapped = STATUS_MAP[cleaned]
      if mapped.nil?
        SwayLogging.warn("[Legistar::StatusMapper] unrecognised MatterStatusName #{status_name.inspect}")
        return nil
      end

      mapped
    end

    def self.known?(status_name)
      return false unless status_name.is_a?(::String)

      cleaned = Sway::Utf8.scrub(status_name).strip.downcase
      STATUS_MAP.key?(cleaned)
    end

    def self.canonical?(status)
      return false unless status.is_a?(::String)

      Bill::STATUSES.include?(status.strip.downcase)
    end
  end
end
