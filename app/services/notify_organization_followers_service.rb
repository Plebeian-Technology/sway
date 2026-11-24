# frozen_string_literal: true

# @lat: [[organization-notification-delivery#Organization notification delivery]]
class NotifyOrganizationFollowersService
  NOTIFICATION_TITLE = "Organization update"

  # @lat: [[organization-notification-delivery#Notification wording names Sway as the recorder]]
  CHANGE_TYPE_COPY = {
    new_position: "Sway recorded %<org>s's position on %<bill>s.",
    support_change: "Sway recorded a change in %<org>s's position on %<bill>s.",
    summary_change: "Sway updated its summary of %<org>s's position on %<bill>s."
  }.freeze #: Hash[NotifyOrganizationFollowersService::change_type, String]

  def initialize(position, change_types:, delivery_token: nil)
    @position = position
    @change_types = Array(change_types).map(&:to_sym)
    @organization = position.organization
    @bill = position.bill
    # @lat: [[organization-notification-delivery#Immediate delivery uses a durable marker]]
    @delivery_token = delivery_token.presence || event_token_for(@position)
  end

  # @lat: [[organization-notification-delivery#Immediate delivery uses a durable marker]]
  def call_later
    NotifyOrganizationFollowersJob.perform_later(
      @organization.id, @bill.id, @change_types.map(&:to_s), @delivery_token
    )
  end

  def call
    # @lat: [[organization-position-removal#Removal deactivates, it does not delete]]
    return unless @position.active

    notifiable_tuples = notifiable_user_ids
    return if notifiable_tuples.empty?

    user_ids = notifiable_tuples.map { |uid, _| uid }
    users_by_id = User.where(id: user_ids).index_by(&:id)

    # @lat: [[organization-notification-delivery#Fan-out batches users and checks the master preference]]
    enabled_user_ids = NotificationPreference
      .where(user_id: user_ids, key: "org_position_taken", enabled: true)
      .pluck(:user_id)
      .to_set

    notifiable_tuples.each do |uid, cadence|
      user = users_by_id[uid]
      next unless user

      next unless enabled_user_ids.include?(uid)

      title = notification_title
      body = notification_body

      case cadence.to_s
      when "every_change"
        dispatch_immediate(user, title, body)
      when "daily", "weekly"
        enqueue_digest(user, cadence.to_s, title, body)
      end
    end
  end

  private

  def notifiable_user_ids
    @organization.notifiable_follower_set_for(@change_types)
  end

  def dispatch_immediate(user, title, body)
    # @lat: [[organization-notification-delivery#Immediate delivery uses a durable marker]]
    return unless mark_delivered_once!(user)

    url = "/bills/#{@bill.id}"

    # @lat: [[organization-notification-delivery#A failed send removes its marker]]
    begin
      OrgNotificationFanout.deliver(user: user, title: title, body: body, url: url)
    rescue
      OrganizationNotificationDelivery.where(
        user_id: user.id,
        organization_bill_position_id: @position.id,
        change_type: delivery_change_key,
        delivery_token: @delivery_token
      ).delete_all
      raise
    end
  end

  def enqueue_digest(user, cadence, _title, _body)
    return unless mark_delivered_once!(user)

    begin
      # @lat: [[organization-notification-delivery#Fan-out batches users and checks the master preference]]
      DigestOrgNotificationAggregator.enqueue(
        user_id: user.id,
        cadence: cadence,
        org_id: @organization.id,
        bill_id: @bill.id,
        change_types: @change_types
      )
    rescue
      OrganizationNotificationDelivery.where(
        user_id: user.id,
        organization_bill_position_id: @position.id,
        change_type: delivery_change_key,
        delivery_token: @delivery_token
      ).delete_all
      raise
    end
  end

  # @lat: [[organization-notification-delivery#Immediate delivery uses a durable marker]]
  def mark_delivered_once!(user)
    OrganizationNotificationDelivery.create!(
      user: user,
      organization_bill_position_id: @position.id,
      change_type: delivery_change_key,
      delivery_token: @delivery_token
    )
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # @lat: [[organization-notification-delivery#Immediate delivery uses a durable marker]]
  def delivery_change_key
    @change_types.map(&:to_s).sort.join(",")
  end

  # @lat: [[organization-notification-delivery#Immediate delivery uses a durable marker]]
  def event_token_for(position)
    (position.updated_at || position.created_at || Time.current).utc.iso8601(6)
  end

  def notification_title
    NOTIFICATION_TITLE
  end

  # @lat: [[bill-title-display#Which outbound messages carry the shortened title]]
  def notification_body
    change_type = (@change_types.size == 1) ? @change_types.first : :support_change
    template = CHANGE_TYPE_COPY.fetch(change_type, CHANGE_TYPE_COPY.fetch(:support_change))
    format(template, org: @organization.name, bill: BillTitle.headline(@bill.title))
  end
end
