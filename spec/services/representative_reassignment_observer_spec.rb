# frozen_string_literal: true

require "rails_helper"

RSpec.describe RepresentativeReassignmentObserver do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:sway_locale) { create(:sway_locale) }

  before do
    clear_enqueued_jobs
  end

  describe ".observe_diff!" do
    context "when a user moves to a new district (district_changed)" do
      it "creates a district_changed record and enqueues DeliverReassignmentNotificationJob" do
        old_dist = create(:district, sway_locale:)
        new_dist = create(:district, sway_locale:)
        old_leg = create(:legislator, district: old_dist)
        new_leg = create(:legislator, district: new_dist)
        old_ul = create(:user_legislator, user:, legislator: old_leg)
        old_ud = create(:user_district, user:, district: old_dist)

        expect {
          described_class.observe_diff!(
            user: user,
            stale_district_ids: [old_dist.id],
            new_district_ids: [new_dist.id],
            stale_legislator_ids: [old_leg.id],
            new_legislator_ids: [new_leg.id],
            stored_uls: [old_ul],
            resolved_legislators: [new_leg],
            stored_user_districts: [old_ud],
            resolved_districts: [new_dist]
          )
        }.to change(RepresentativeReassignment, :count).by(1)
          .and have_enqueued_job(DeliverReassignmentNotificationJob).with(user.id)

        reassignment = RepresentativeReassignment.last
        expect(reassignment.reassignment_type).to eq("district_changed")
        expect(reassignment.district).to eq(new_dist)
        expect(reassignment.previous_district).to eq(old_dist)
        expect(reassignment.legislator).to eq(new_leg)
        expect(reassignment.previous_legislator).to eq(old_leg)
      end
    end

    context "when a successor is seeded for the same seat (successor_seeded)" do
      it "creates a successor_seeded record" do
        district = create(:district, sway_locale:)
        old_leg = create(:legislator, district:)
        new_leg = create(:legislator, district:)
        old_ul = create(:user_legislator, user:, legislator: old_leg)
        old_ud = create(:user_district, user:, district:)

        expect {
          described_class.observe_diff!(
            user: user,
            stale_district_ids: [],
            new_district_ids: [],
            stale_legislator_ids: [old_leg.id],
            new_legislator_ids: [new_leg.id],
            stored_uls: [old_ul],
            resolved_legislators: [new_leg],
            stored_user_districts: [old_ud],
            resolved_districts: [district]
          )
        }.to change(RepresentativeReassignment, :count).by(1)

        reassignment = RepresentativeReassignment.last
        expect(reassignment.reassignment_type).to eq("successor_seeded")
        expect(reassignment.district).to eq(district)
        expect(reassignment.legislator).to eq(new_leg)
        expect(reassignment.previous_legislator).to eq(old_leg)
      end

      it "pairs stale and new legislators by matching district_id rather than positional order" do
        dist_a = create(:district, sway_locale:, name: "MD1")
        dist_b = create(:district, sway_locale:, name: "MD2")
        old_leg_a = create(:legislator, sway_locale:)
        create(:legislator_term, :prior_term, legislator: old_leg_a, district: dist_a)
        old_leg_b = create(:legislator, sway_locale:)
        create(:legislator_term, :prior_term, legislator: old_leg_b, district: dist_b)

        new_leg_b = create(:legislator, district: dist_b)
        create(:legislator_term, legislator: new_leg_b, district: dist_b)
        new_leg_a = create(:legislator, district: dist_a)
        create(:legislator_term, legislator: new_leg_a, district: dist_a)

        old_ul_a = create(:user_legislator, user:, legislator: old_leg_a)
        old_ul_b = create(:user_legislator, user:, legislator: old_leg_b)
        old_ud_a = create(:user_district, user:, district: dist_a)
        old_ud_b = create(:user_district, user:, district: dist_b)

        described_class.observe_diff!(
          user: user,
          stale_district_ids: [],
          new_district_ids: [],
          stale_legislator_ids: [old_leg_a.id, old_leg_b.id],
          new_legislator_ids: [new_leg_b.id, new_leg_a.id],
          stored_uls: [old_ul_a, old_ul_b],
          resolved_legislators: [new_leg_b, new_leg_a],
          stored_user_districts: [old_ud_a, old_ud_b],
          resolved_districts: [dist_a, dist_b]
        )

        reassignment_a = user.representative_reassignments.find_by!(previous_legislator: old_leg_a)
        reassignment_b = user.representative_reassignments.find_by!(previous_legislator: old_leg_b)
        expect(reassignment_a.legislator).to eq(new_leg_a)
        expect(reassignment_a.district).to eq(dist_a)
        expect(reassignment_b.legislator).to eq(new_leg_b)
        expect(reassignment_b.district).to eq(dist_b)
      end
    end

    context "when a seat becomes vacant (vacant_seat)" do
      it "creates a vacant_seat record with nil legislator" do
        district = create(:district, sway_locale:)
        old_leg = create(:legislator, district:)
        old_ul = create(:user_legislator, user:, legislator: old_leg)
        old_ud = create(:user_district, user:, district:)

        expect {
          described_class.observe_diff!(
            user: user,
            stale_district_ids: [district.id],
            new_district_ids: [],
            stale_legislator_ids: [old_leg.id],
            new_legislator_ids: [],
            stored_uls: [old_ul],
            resolved_legislators: [],
            stored_user_districts: [old_ud],
            resolved_districts: []
          )
        }.to change(RepresentativeReassignment, :count).by(1)

        reassignment = RepresentativeReassignment.last
        expect(reassignment.reassignment_type).to eq("vacant_seat")
        expect(reassignment.district).to eq(district)
        expect(reassignment.legislator).to be_nil
        expect(reassignment.previous_legislator).to eq(old_leg)
      end
    end

    context "when a seat is filled from vacancy (vacancy_filled)" do
      it "creates a vacancy_filled record with nil previous_legislator" do
        district = create(:district, sway_locale:)
        new_leg = create(:legislator, district:)

        expect {
          described_class.observe_diff!(
            user: user,
            stale_district_ids: [],
            new_district_ids: [],
            stale_legislator_ids: [],
            new_legislator_ids: [new_leg.id],
            stored_uls: [],
            resolved_legislators: [new_leg],
            stored_user_districts: [],
            resolved_districts: [district]
          )
        }.to change(RepresentativeReassignment, :count).by(1)

        reassignment = RepresentativeReassignment.last
        expect(reassignment.reassignment_type).to eq("vacancy_filled")
        expect(reassignment.district).to eq(district)
        expect(reassignment.legislator).to eq(new_leg)
        expect(reassignment.previous_legislator).to be_nil
      end
    end

    context "when diff is empty or already recorded (idempotency)" do
      it "creates zero records and does not enqueue delivery" do
        expect {
          described_class.observe_diff!(
            user: user,
            stale_district_ids: [],
            new_district_ids: [],
            stale_legislator_ids: [],
            new_legislator_ids: [],
            stored_uls: [],
            resolved_legislators: [],
            stored_user_districts: [],
            resolved_districts: []
          )
        }.not_to change(RepresentativeReassignment, :count)

        expect(enqueued_jobs).to be_empty
      end

      it "deduplicates repeated sweeps and rescues RecordNotUnique collisions without re-enqueuing notifications" do
        district = create(:district, sway_locale:)
        old_leg = create(:legislator, district:)
        new_leg = create(:legislator, district:)
        old_ul = create(:user_legislator, user:, legislator: old_leg)
        old_ud = create(:user_district, user:, district:)

        args = {
          user: user,
          stale_district_ids: [],
          new_district_ids: [],
          stale_legislator_ids: [old_leg.id],
          new_legislator_ids: [new_leg.id],
          stored_uls: [old_ul],
          resolved_legislators: [new_leg],
          stored_user_districts: [old_ud],
          resolved_districts: [district]
        }

        expect {
          described_class.observe_diff!(**args)
        }.to change(RepresentativeReassignment, :count).by(1)
          .and have_enqueued_job(DeliverReassignmentNotificationJob).with(user.id)

        clear_enqueued_jobs
        expect {
          described_class.observe_diff!(**args)
        }.not_to change(RepresentativeReassignment, :count)
        expect(enqueued_jobs).to be_empty
      end
    end
  end
end
