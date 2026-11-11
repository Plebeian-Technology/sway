# frozen_string_literal: true

# @lat: [[query-plan-indexes#Single-column indexes a composite already covers]]
class DropRedundantSingleColumnIndexes < ActiveRecord::Migration[8.1]
  REDUNDANT_INDEXES = [
    [:user_votes, :user_id, "index_user_votes_on_user_id"],
    [:bill_score_districts, :bill_score_id, "index_bill_score_districts_on_bill_score_id"],
    [:legislator_votes, :bill_id, "index_legislator_votes_on_bill_id"],
    [:user_legislators, :user_id, "index_user_legislators_on_user_id"],
    [:admin_bill_views, :admin_user_id, "index_admin_bill_views_on_admin_user_id"],
    [:bill_categories, :bill_id, "index_bill_categories_on_bill_id"],
    [:notification_preferences, :user_id, "index_notification_preferences_on_user_id"],
    [:organization_follows, :user_id, "index_organization_follows_on_user_id"],
    [:push_notification_subscriptions, :user_id, "index_push_notification_subscriptions_on_user_id"],
    [:sending_service_domain_bills, :sending_service_domain_id, "idx_on_sending_service_domain_id_e1e249513f"]
  ].freeze

  def up
    REDUNDANT_INDEXES.each do |table, _column, name|
      remove_index table, name: name if index_name_exists?(table, name)
    end
  end

  def down
    REDUNDANT_INDEXES.each do |table, column, name|
      add_index table, column, name: name unless index_name_exists?(table, name)
    end
  end
end
