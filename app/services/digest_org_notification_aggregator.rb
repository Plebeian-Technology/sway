# frozen_string_literal: true

# @lat: [[pending-org-digest-entry-design#Why PendingOrganizationDigestEntry is a durable queue]]
class DigestOrgNotificationAggregator
  RECIPIENT_BATCH_SIZE = 100

  def self.enqueue(user_id:, cadence:, org_id:, bill_id:, change_types:)
    PendingOrganizationDigestEntry.create!(
      user_id: user_id,
      cadence: cadence.to_s,
      org_id: org_id,
      bill_id: bill_id,
      change_types: Array(change_types).join(",")
    )
  end

  def self.dispatch_period(cadence, batch_size: RECIPIENT_BATCH_SIZE)
    cadence_str = cadence.to_s
    cursor = nil

    loop do
      # @lat: [[pending-org-digest-entry-design#Why dispatch_period uses keyset pagination by recipient]]
      scope = PendingOrganizationDigestEntry.where(cadence: cadence_str)
      scope = scope.where("user_id > ?", cursor) if cursor
      batch_user_ids = scope.order(:user_id).distinct.limit(batch_size).pluck(:user_id)
      break if batch_user_ids.empty?

      cursor = batch_user_ids.last

      users_by_id = User.where(id: batch_user_ids).index_by(&:id)

      # @lat: [[pending-org-digest-entry-design#Why the master gate is re-checked at dispatch]]
      enabled_user_ids = NotificationPreference
        .where(user_id: batch_user_ids, key: "org_position_taken", enabled: true)
        .pluck(:user_id)
        .to_set

      # @lat: [[pending-org-digest-entry-design#Why dispatch_period selects with no created_at window]]
      batch_entries = PendingOrganizationDigestEntry
        .where(cadence: cadence_str, user_id: batch_user_ids)
        .order(:user_id, :created_at)
        .to_a
      entries_by_user = batch_entries.group_by(&:user_id)

      batch_org_ids = batch_entries.map(&:org_id).uniq
      org_names_by_id = Organization.where(id: batch_org_ids).pluck(:id, :name).to_h

      batch_user_ids.each do |uid|
        rows = entries_by_user[uid]
        next if rows.blank?

        row_ids = rows.map(&:id)
        user = users_by_id[uid]

        # @lat: [[pending-org-digest-entry-design#Why rows are claimed before sending]]
        deleted_count = 0
        PendingOrganizationDigestEntry.transaction do
          row_ids.each_slice(1000) do |slice|
            deleted_count += PendingOrganizationDigestEntry.where(id: slice).delete_all
          end
        end

        next if deleted_count.zero?
        next unless user && enabled_user_ids.include?(uid)

        org_names = rows.map(&:org_id).uniq.filter_map { |id| org_names_by_id[id] }
        next if org_names.empty?

        period_label = (cadence_str == "weekly") ? "this week" : "today"
        title, body = build_digest_copy(org_names, rows.size, period_label)
        url = "/organizations"

        OrgNotificationFanout.deliver(user: user, title: title, body: body, url: url)
      end
    end
  end

  def self.build_digest_copy(org_names, _change_count, period_label)
    if org_names.size == 1
      title = org_names.first
      body = "#{org_names.first} updated their positions #{period_label}."
    else
      first = org_names.first
      others = [org_names.size - 1, 0].max
      title = first
      body = "#{first} and #{others} other #{"organization".pluralize(others)} updated their positions #{period_label}."
    end
    [title, body]
  end
  private_class_method :build_digest_copy
end
