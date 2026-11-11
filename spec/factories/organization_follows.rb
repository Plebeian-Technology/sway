# == Schema Information
#
# Table name: organization_follows
# Database name: primary
#
#  id                       :integer          not null, primary key
#  notification_cadence     :integer          default("every_change"), not null
#  notify_on_new_position   :boolean          default(TRUE), not null
#  notify_on_summary_change :boolean          default(TRUE), not null
#  notify_on_support_change :boolean          default(TRUE), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  organization_id          :integer          not null
#  user_id                  :integer          not null
#
# Indexes
#
#  idx_organization_follows_on_user_and_organization  (user_id,organization_id) UNIQUE
#  index_organization_follows_on_organization_id      (organization_id)
#
# Foreign Keys
#
#  organization_id  (organization_id => organizations.id)
#  user_id          (user_id => users.id)
#
FactoryBot.define do
  factory :organization_follow do
    user
    organization

    # Notification preference columns, set to the values the model defaults to.
    # The database would fill them in on its own (they are NOT NULL with a
    # DEFAULT); they are written out here so a reader can see them and so traits
    # can override them.
    notification_cadence { :every_change }
    notify_on_new_position { true }
    notify_on_support_change { true }
    notify_on_summary_change { true }

    trait :daily_cadence do
      notification_cadence { :daily }
    end

    trait :weekly_cadence do
      notification_cadence { :weekly }
    end

    trait :muted do
      notify_on_new_position { false }
      notify_on_support_change { false }
      notify_on_summary_change { false }
    end
  end
end
