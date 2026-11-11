# frozen_string_literal: true

# == Schema Information
#
# Table name: organization_notification_deliveries
# Database name: primary
#
#  id                            :integer          not null, primary key
#  change_type                   :string           not null
#  delivery_token                :string           not null
#  created_at                    :datetime         not null
#  organization_bill_position_id :integer          not null
#  user_id                       :integer          not null
#
# Indexes
#
#  idx_org_notif_deliveries_unique                        (organization_bill_position_id,user_id,change_type,delivery_token) UNIQUE
#  index_organization_notification_deliveries_on_user_id  (user_id)
#
# @lat: [[notify-organization-followers-job-design#The sent-marker table: OrgNotificationDelivery]]
class OrganizationNotificationDelivery < ApplicationRecord
  self.table_name = "organization_notification_deliveries"
  belongs_to :user
end
