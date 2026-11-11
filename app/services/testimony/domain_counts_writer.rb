# frozen_string_literal: true

module Testimony
  # @lat: [[domain-panel-totals#Where the domain panel's totals come from]]
  # @lat: [[domain-panel-totals#Why domain labels are set only by an operator]]
  class DomainCountsWriter
    class << self
      def call(bill:, letters:)
        new(bill: bill, letters: letters).call
      end
    end

    def initialize(bill:, letters:)
      @bill = bill
      @letters = letters
    end

    # @lat: [[domain-panel-totals#Where the domain panel's totals come from]]
    def call
      contributions = build_contributions

      SendingServiceDomainBill.transaction do
        current_domain_ids = contributions.keys.map { |domain_name| SendingServiceDomain.find_or_create_by!(domain: domain_name).id }
        SendingServiceDomainBill.where(bill: @bill).where.not(sending_service_domain_id: current_domain_ids).delete_all

        contributions.each do |domain_name, counts|
          domain = SendingServiceDomain.find_by!(domain: domain_name)
          SendingServiceDomainBill.record_contribution!(
            sending_service_domain: domain,
            bill: @bill,
            sender_count: counts.fetch(:sender_count),
            letter_count: counts.fetch(:letter_count),
            machine_sent_letter_count: counts.fetch(:machine_sent_letter_count)
          )
        end

        collect_unlabelled_orphans
      end

      contributions
    end

    private

    # @lat: [[domain-panel-totals#Why DomainCountsWriter re-validates domains and deletes unlabelled orphans]]
    def collect_unlabelled_orphans
      SendingServiceDomain
        .where(label: SendingServiceDomain::NO_LABEL)
        .where.missing(:sending_service_domain_bills)
        .delete_all
    end

    # @lat: [[domain-panel-totals#Why DomainCountsWriter re-validates domains and deletes unlabelled orphans]]
    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a repeat letter is marked, not hidden]]
    def build_contributions
      active_letters = @letters.reject { |letter| letter["excluded"] == true }
      by_domain = active_letters.group_by { |letter| letter["sender_domain"] }
      by_domain.select! { |domain_name, _| Testimony::SenderDomain.valid?(domain_name) }

      by_domain.transform_values do |domain_letters|
        counted = domain_letters.reject { |letter| letter["repeat"] }
        {
          sender_count: counted.pluck("sender_address").uniq.length,
          letter_count: counted.length,
          machine_sent_letter_count: counted.count { |letter| letter["campaign_origin"] }
        }
      end
    end
  end
end
