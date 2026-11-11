# frozen_string_literal: true

# == Schema Information
#
# Table name: sending_service_domains
# Database name: primary
#
#  id              :integer          not null, primary key
#  confirmed_at    :datetime
#  domain          :string           not null
#  label           :string           default("none"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  confirmed_by_id :integer
#
# Indexes
#
#  index_sending_service_domains_on_confirmed_by_id  (confirmed_by_id)
#  index_sending_service_domains_on_domain           (domain) UNIQUE
#
# Foreign Keys
#
#  confirmed_by_id  (confirmed_by_id => users.id)
#
class SendingServiceDomain < ApplicationRecord
  # @lat: [[domain-panel-totals#Why the domain panel bounds, filters, and validates untrusted domains]]
  NO_LABEL = "none"
  PROPOSED = "proposed"
  CONFIRMED = "confirmed"
  LABELS = [NO_LABEL, PROPOSED, CONFIRMED].freeze

  # @lat: [[domain-panel-totals#Why the domain panel bounds, filters, and validates untrusted domains]]
  MAX_PANEL_ROWS = 200

  belongs_to :confirmed_by, class_name: "User", optional: true

  has_many :sending_service_domain_bills,
    inverse_of: :sending_service_domain,
    dependent: :destroy

  # @lat: [[domain-panel-totals#Why the domain panel bounds, filters, and validates untrusted domains]]
  validates :domain, presence: true, uniqueness: true,
    length: {maximum: Testimony::SenderDomain::MAX_CHARS},
    format: {with: Testimony::SenderDomain::FORMAT}
  validates :label, inclusion: {in: LABELS}

  # @lat: [[domain-panel-totals#Why the domain panel bounds, filters, and validates untrusted domains]]
  scope :for_panel, -> {
    where(id: SendingServiceDomainBill.select(:sending_service_domain_id))
      .or(where.not(label: NO_LABEL))
  }

  # @lat: [[domain-panel-totals#Why the aliases are spelled in one place]]
  PANEL_TOTALS = {
    machine_sent_letter_count: "COALESCE(SUM(sending_service_domain_bills.machine_sent_letter_count), 0)",
    sender_count: "COALESCE(SUM(sending_service_domain_bills.sender_count), 0)",
    letter_count: "COALESCE(SUM(sending_service_domain_bills.letter_count), 0)",
    bill_count: "COUNT(sending_service_domain_bills.id)"
  }.freeze

  def self.summed_alias(column)
    :"summed_#{column}"
  end

  def self.panel_total_selections
    PANEL_TOTALS.map { |column, expression| "#{expression} AS #{summed_alias(column)}" }
  end

  # @lat: [[domain-panel-totals#Why the panel computes the totals in one query]]
  scope :panel_ranked, -> {
    left_joins(:sending_service_domain_bills)
      .group(:id)
      .select("sending_service_domains.*", SendingServiceDomain.panel_total_selections)
      .order(Arel.sql("summed_machine_sent_letter_count DESC"), :domain)
      .limit(MAX_PANEL_ROWS)
  }

  # @lat: [[domain-panel-totals#Where the domain panel's totals come from]]
  # @lat: [[domain-panel-totals#Why the readers read the attribute rather than call the alias]]
  def sender_count
    summed_or_query(:sender_count) { sending_service_domain_bills.sum(:sender_count) }
  end

  def letter_count
    summed_or_query(:letter_count) { sending_service_domain_bills.sum(:letter_count) }
  end

  def machine_sent_letter_count
    summed_or_query(:machine_sent_letter_count) { sending_service_domain_bills.sum(:machine_sent_letter_count) }
  end

  def bill_count
    summed_or_query(:bill_count) { sending_service_domain_bills.count }
  end

  private

  def summed_or_query(column)
    alias_name = self.class.summed_alias(column)
    has_attribute?(alias_name) ? self[alias_name] : yield
  end
end
