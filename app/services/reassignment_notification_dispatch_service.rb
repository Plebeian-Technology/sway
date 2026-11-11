# frozen_string_literal: true

class ReassignmentNotificationDispatchService
  PREFERENCE_KEY = "legislator_updates"

  def initialize(user_id = nil)
    @user_id = user_id
  end

  def call(user_id = @user_id)
    user = user_id.is_a?(User) ? user_id : User.find_by(id: user_id)
    return if user.nil?

    claimed = claim_pending_delivery(user)
    return if claimed.empty?

    begin
      pref = user.notification_preferences.find_by(key: PREFERENCE_KEY)
      return unless pref&.enabled?

      deliver_push(user, claimed)
      deliver_email(user, claimed)
    rescue
      RepresentativeReassignment.where(id: claimed.map(&:id)).update_all(notified_at: nil)
      raise
    end
  end

  private

  def claim_pending_delivery(user)
    RepresentativeReassignment.transaction do
      claimed = user.representative_reassignments
        .pending_delivery
        .lock
        .includes(:district, :previous_district, :legislator, :previous_legislator)
        .to_a
      return [] if claimed.empty?

      now = Time.current
      RepresentativeReassignment.where(id: claimed.map(&:id)).update_all(notified_at: now)
      claimed
    end
  end

  def deliver_push(user, reassignments)
    title, body = build_push_copy(reassignments)
    url = "/legislators"

    PushNotificationSubscription.active.where(user_id: user.id).find_each do |sub|
      SwayPushNotificationService.new(sub, title: title, body: body, url: url).send_push_notification
    end

    user.user_devices.active.find_each do |device|
      SendNativePushJob.perform_later(
        device.id,
        {kind: PREFERENCE_KEY, title: title, body: body, data: {url: url}}
      )
    end
  end

  def deliver_email(user, reassignments)
    return unless user.email.present? && user.is_email_verified?

    RepresentativeReassignmentMailer.reassignment_digest(user, reassignments).deliver_later
  end

  def build_push_copy(reassignments)
    if reassignments.size == 1
      reassignment = reassignments.first
      case reassignment.reassignment_type
      when "successor_seeded"
        ["Representative Update", "#{reassignment.legislator&.full_name} has succeeded #{reassignment.previous_legislator&.full_name} as your representative."]
      when "district_changed"
        district_name = reassignment.district&.name || "a new district"
        ["District Update", "Your voting district has changed to #{district_name}."]
      when "vacant_seat"
        district_name = reassignment.district&.name || "your district"
        ["Representation Notice", "The seat for #{district_name} is currently vacant."]
      when "vacancy_filled"
        district_name = reassignment.district&.name || "your district"
        ["Representative Seated", "#{reassignment.legislator&.full_name} now represents #{district_name}."]
      else
        ["Representative Update", "Your elected representatives have been updated."]
      end
    else
      ["Representative Updates", "#{reassignments.size} of your elected representatives have been updated on Sway."]
    end
  end
end
