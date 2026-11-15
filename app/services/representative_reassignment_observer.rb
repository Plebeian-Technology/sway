# frozen_string_literal: true

class RepresentativeReassignmentObserver
  PRESIDENT_SEAT_IDENTIFIER = "us-president"

  def self.observe_diff!(
    user:,
    stale_district_ids:,
    new_district_ids:,
    stale_legislator_ids:,
    new_legislator_ids:,
    stored_uls:,
    resolved_legislators:,
    stored_user_districts:,
    resolved_districts:
  )
    new.observe_diff!(
      user:,
      stale_district_ids:,
      new_district_ids:,
      stale_legislator_ids:,
      new_legislator_ids:,
      stored_uls:,
      resolved_legislators:,
      stored_user_districts:,
      resolved_districts:
    )
  end

  def observe_diff!(user:, stale_district_ids:, new_district_ids:, stale_legislator_ids:, new_legislator_ids:, stored_uls:, resolved_legislators:, stored_user_districts:, resolved_districts:)
    created_any = false

    stale_legs = stored_uls.select { |ul| stale_legislator_ids.include?(ul.legislator_id) }.map(&:legislator).compact
    new_legs = resolved_legislators.select { |l| new_legislator_ids.include?(l.id) }.reject { |l| president?(l) }
    president_district_ids = resolved_legislators.select { |l| president?(l) }.filter_map { |l| district_for(l)&.id }
    new_district_ids -= president_district_ids
    stale_dists = stored_user_districts.select { |ud| stale_district_ids.include?(ud.district_id) }.map(&:district).compact.uniq(&:id)
    new_dists = resolved_districts.select { |d| new_district_ids.include?(d.id) }.uniq(&:id)

    remaining_stale_legs = stale_legs.dup
    remaining_new_legs = new_legs.dup

    if stale_district_ids.blank? && new_district_ids.blank?
      pairs, remaining_stale_legs, remaining_new_legs = pair_legislators(remaining_stale_legs, remaining_new_legs)
      pairs.each do |old_leg, new_leg|
        dist = district_for(new_leg) || district_for(old_leg) || resolved_districts.first || stored_user_districts.first&.district
        record = persist_reassignment(
          user: user,
          reassignment_type: :successor_seeded,
          district: dist,
          previous_district: dist,
          legislator: new_leg,
          previous_legislator: old_leg
        )
        created_any = true if record
      end
    elsif stale_district_ids.present? && new_district_ids.present?
      pairs, remaining_stale_legs, remaining_new_legs = pair_legislators(remaining_stale_legs, remaining_new_legs)
      pairs.each_with_index do |(old_leg, new_leg), i|
        old_dist = district_for(old_leg) || stale_dists[i] || stale_dists.first || stored_user_districts.first&.district
        new_dist = district_for(new_leg) || new_dists[i] || new_dists.first || resolved_districts.first
        record = persist_reassignment(
          user: user,
          reassignment_type: :district_changed,
          district: new_dist,
          previous_district: old_dist,
          legislator: new_leg,
          previous_legislator: old_leg
        )
        created_any = true if record
      end
    end

    while (old_leg = remaining_stale_legs.shift)
      dist = district_for(old_leg) || stale_dists.first || stored_user_districts.first&.district
      record = persist_reassignment(
        user: user,
        reassignment_type: :vacant_seat,
        district: dist,
        previous_district: nil,
        legislator: nil,
        previous_legislator: old_leg
      )
      created_any = true if record
    end

    while (new_leg = remaining_new_legs.shift)
      new_dist = district_for(new_leg) || new_dists.first || resolved_districts.first
      type = (stale_district_ids.present? && stale_dists.present?) ? :district_changed : :vacancy_filled
      prev_dist = (type == :district_changed) ? (stale_dists.first || stored_user_districts.first&.district) : nil
      record = persist_reassignment(
        user: user,
        reassignment_type: type,
        district: new_dist,
        previous_district: prev_dist,
        legislator: new_leg,
        previous_legislator: nil
      )
      created_any = true if record
    end

    if created_any
      DeliverReassignmentNotificationJob.set(wait: 2.minutes).perform_later(user.id)
    end
  end

  private

  def president?(legislator)
    legislator.active_term&.seat&.seat_identifier == PRESIDENT_SEAT_IDENTIFIER
  end

  def district_for(legislator)
    legislator.district || legislator.legislator_terms.order(term_start_year: :desc, id: :desc).first&.district
  end

  def seat_id_for(legislator)
    legislator.active_term&.seat_id || legislator.legislator_terms.order(term_start_year: :desc, id: :desc).first&.seat_id
  end

  def pair_legislators(stale_legs, new_legs)
    pairs = [] #: Array[[Legislator, Legislator]]
    unpaired_stale = [] #: Array[Legislator]
    pool_new = new_legs.dup

    stale_legs.each do |old_leg|
      old_seat_id = seat_id_for(old_leg)
      old_dist_id = district_for(old_leg)&.id

      match_idx =
        (old_seat_id && pool_new.index { |nl| seat_id_for(nl) == old_seat_id }) ||
        (old_dist_id && pool_new.index { |nl| district_for(nl)&.id == old_dist_id })

      if match_idx
        matched_new = pool_new.delete_at(match_idx)
        pairs << [old_leg, matched_new] if matched_new
      else
        unpaired_stale << old_leg
      end
    end

    while unpaired_stale.any? && pool_new.any?
      old_leg = unpaired_stale.shift
      new_leg = pool_new.shift
      pairs << [old_leg, new_leg] if old_leg && new_leg
    end

    [pairs, unpaired_stale, pool_new]
  end

  def persist_reassignment(user:, reassignment_type:, district:, previous_district:, legislator:, previous_legislator:)
    existing = user.representative_reassignments.find_by(
      district_id: district&.id,
      previous_district_id: previous_district&.id,
      legislator_id: legislator&.id,
      previous_legislator_id: previous_legislator&.id,
      reassignment_type: reassignment_type
    )
    return nil if existing

    user.representative_reassignments.create!(
      district: district,
      previous_district: previous_district,
      legislator: legislator,
      previous_legislator: previous_legislator,
      reassignment_type: reassignment_type
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
