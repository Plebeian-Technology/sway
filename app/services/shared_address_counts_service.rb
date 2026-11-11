# frozen_string_literal: true

# @lat: [[personal-detail-encryption#Why the shared-addresses admin page reports counts only]]
class SharedAddressCountsService
  MIN_SHARED_USERS = 2

  def self.rows
    new.rows
  end

  def rows
    counted = groups_by_key.values.map { |group|
      {address_ids: group[:address_ids].uniq.sort, user_count: group[:user_ids].uniq.size}
    } #: Array[Hash[Symbol, untyped]]

    counted
      .select { |row| row[:user_count] >= MIN_SHARED_USERS }
      .sort_by { |row| -row[:user_count] }
  end

  private

  def groups_by_key
    grouped = Hash.new { |hash, key| hash[key] = {user_ids: [], address_ids: []} }
    address_user_rows.each do |address_id, user_id, normalized_key|
      key = normalized_key || "address:#{address_id}"
      grouped[key][:user_ids] << user_id
      grouped[key][:address_ids] << address_id
    end
    grouped
  end

  def address_user_rows
    UserAddress.joins(:address).pluck(:address_id, :user_id, "addresses.normalized_key")
  end
end
