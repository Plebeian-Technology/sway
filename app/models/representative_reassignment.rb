# frozen_string_literal: true

# == Schema Information
#
# Table name: representative_reassignments
# Database name: primary
#
#  id                     :integer          not null, primary key
#  dismissed_at           :datetime
#  notified_at            :datetime
#  reassignment_type      :integer          default("district_changed"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  district_id            :integer
#  legislator_id          :integer
#  previous_district_id   :integer
#  previous_legislator_id :integer
#  user_id                :integer          not null
#
# Indexes
#
#  idx_rep_reassign_filled_unique                                (user_id,district_id,legislator_id) UNIQUE WHERE previous_legislator_id IS NULL
#  idx_rep_reassign_full_unique                                  (user_id,district_id,legislator_id,previous_legislator_id) UNIQUE WHERE previous_legislator_id IS NOT NULL AND legislator_id IS NOT NULL
#  idx_rep_reassign_user_active                                  (user_id,dismissed_at)
#  idx_rep_reassign_vacant_unique                                (user_id,district_id,previous_legislator_id) UNIQUE WHERE legislator_id IS NULL
#  index_representative_reassignments_on_district_id             (district_id)
#  index_representative_reassignments_on_legislator_id           (legislator_id)
#  index_representative_reassignments_on_previous_district_id    (previous_district_id)
#  index_representative_reassignments_on_previous_legislator_id  (previous_legislator_id)
#  index_representative_reassignments_on_user_id                 (user_id)
#
# Foreign Keys
#
#  district_id             (district_id => districts.id)
#  legislator_id           (legislator_id => legislators.id)
#  previous_district_id    (previous_district_id => districts.id)
#  previous_legislator_id  (previous_legislator_id => legislators.id)
#  user_id                 (user_id => users.id) ON DELETE => cascade
#
class RepresentativeReassignment < ApplicationRecord
  enum :reassignment_type, {
    district_changed: 0,
    successor_seeded: 1,
    vacant_seat: 2,
    vacancy_filled: 3
  }

  belongs_to :user
  belongs_to :district, optional: true
  belongs_to :previous_district, class_name: "District", optional: true
  belongs_to :legislator, optional: true
  belongs_to :previous_legislator, class_name: "Legislator", optional: true

  scope :pending_in_app, -> { where(dismissed_at: nil).order(created_at: :desc) }
  scope :pending_delivery, -> { where(notified_at: nil) }

  def dismiss!
    touch(:dismissed_at)
  end
end
