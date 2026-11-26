# frozen_string_literal: true

# @lat: [[mobile-admin-area#The user address changes screen]]
module Admin
  class UserAddressChangesController < ApplicationController
    before_action :verify_is_sway_admin

    def show
      records = UserAddressChange.order(created_at: :desc, id: :desc).limit(100).to_a
      locale_ids = records.flat_map { |record| record.previous_sway_locale_ids + record.new_sway_locale_ids }.uniq
      locale_names_by_id =
        if locale_ids.empty?
          {}
        else
          SwayLocale.where(id: locale_ids).to_h { |locale| [locale.id, locale.name] }
        end
      user_ids = records.map(&:user_id).uniq
      switch_counts_by_user_id =
        if user_ids.empty?
          {}
        else
          UserAddressChange.where(user_id: user_ids).group(:user_id).count
        end

      render_inertia_or_json(
        page: Pages::ADMIN_USER_ADDRESS_CHANGES,
        props: {
          user_address_changes: UserAddressChangeResource.new(
            records,
            params: {locale_names_by_id:, switch_counts_by_user_id:}
          ).serializable_hash
        }
      )
    end
  end
end
