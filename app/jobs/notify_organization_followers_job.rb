# frozen_string_literal: true

# @lat: [[notify-organization-followers-job-design#Why dispatch_immediate deletes the marker on a send failure instead of rolling back]]
class NotifyOrganizationFollowersJob < ApplicationJob
  queue_as :default

  # @lat: [[notify-organization-followers-job-design#Why delivery_token defaults to nil and is passed through verbatim]]
  def perform(organization_id, bill_id, change_type_strings, delivery_token = nil)
    # @lat: [[bill-session-archiving#Bill session archiving#Ingestion and pending work]]
    position = OrganizationBillPosition.joins(:bill).find_by(
      organization_id: organization_id, bill_id: bill_id
    )
    return unless position

    change_types = change_type_strings.map(&:to_sym)
    NotifyOrganizationFollowersService.new(
      position, change_types: change_types, delivery_token: delivery_token
    ).call
  end
end
