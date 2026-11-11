# frozen_string_literal: true

# @lat: [[domain-panel-totals#Why domain labels are set only by an operator]]
class SetSendingServiceDomainLabelService
  SETTABLE_LABELS = [SendingServiceDomain::CONFIRMED, SendingServiceDomain::NO_LABEL].freeze

  def initialize(domain:, actor:, label:)
    @domain = domain
    @actor = actor
    @label = label.to_s
  end

  def call
    return :invalid_label unless SETTABLE_LABELS.include?(@label)

    return confirm! if @label == SendingServiceDomain::CONFIRMED

    remove!
  end

  private

  # @lat: [[domain-panel-totals#Why domain labels are set only by an operator]]
  def confirm!
    return :confirmed if @domain.label == SendingServiceDomain::CONFIRMED

    @domain.update!(
      label: SendingServiceDomain::CONFIRMED,
      confirmed_by: @actor,
      confirmed_at: Time.current
    )
    :confirmed
  end

  def remove!
    @domain.update!(
      label: SendingServiceDomain::NO_LABEL,
      confirmed_by: nil,
      confirmed_at: nil
    )
    :removed
  end
end
