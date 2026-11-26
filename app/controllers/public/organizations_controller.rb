# frozen_string_literal: true

# @lat: [[public-organizations-endpoint]]
module Public
  class OrganizationsController < ApplicationController
    skip_before_action :authenticate_sway_user!, only: %i[index show]

    MAX_ORGANIZATIONS_PER_INDEX_PAGE = 100

    def index
      scope = Organization.all
      filter_locale_id = params[:sway_locale_id].presence || params[:locale_id].presence
      # @lat: [[public-organizations-endpoint#Why the web list defaults to the current locale and JSON does not]]
      filter_locale_id ||= current_sway_locale&.id&.to_s unless mobile_api_request?
      scope = scope.where(sway_locale_id: filter_locale_id) if filter_locale_id.present?

      # @lat: [[public-organizations-endpoint#Why the name search escapes its own wildcards]]
      org_search = params[:org_search].presence if params[:org_search].is_a?(String)
      if org_search
        pattern = "%#{Organization.sanitize_sql_like(org_search)}%"
        scope = scope.where(Organization.arel_table[:name].matches(pattern, "\\"))
      end

      if ActiveModel::Type::Boolean.new.cast(params[:following]) && current_user
        scope = scope.joins(:organization_follows)
          .where(organization_follows: {user_id: current_user.id})
      end

      # @lat: [[public-organizations-endpoint#The public organizations endpoint#Why the list preloads icons and the detail does not]]
      orgs = scope.with_attached_icon.includes(:sway_locale).order(:name).limit(MAX_ORGANIZATIONS_PER_INDEX_PAGE)
      managed_ids = Organization.managed_on_sway_ids(orgs.map(&:id)).to_set

      props = {
        organizations: orgs.map { |org| org.to_public_json(managed_on_sway: managed_ids.include?(org.id)) },
        applied_filters: {
          locale_id: filter_locale_id,
          sway_locale_id: filter_locale_id,
          org_search: org_search
        }
      }

      # @lat: [[public-organizations-endpoint#What a signed-out reader is never sent]]
      if current_user
        follows = current_user
          .organization_follows
          .where(organization_id: orgs.map(&:id))
          .select(:id, :organization_id, :notification_cadence,
            :notify_on_new_position, :notify_on_support_change, :notify_on_summary_change)
          .to_a

        props[:user_follows] = follows.each_with_object({}) do |follow, acc|
          acc[follow.organization_id] = follow.id
        end
        props[:user_follow_prefs] = follows.each_with_object({}) do |follow, acc|
          acc[follow.organization_id] = follow_prefs_payload(follow)
        end
        props[:current_user_org_defaults] = org_defaults_payload(current_user)
        props[:is_member_of_org_ids] = current_user
          .user_organization_memberships
          .where(status: :active)
          .pluck(:organization_id)
      end

      render_inertia_or_json(
        page: Pages::ORGANIZATIONS,
        props: props
      )
    end

    def show
      # @lat: [[public-organizations-endpoint#The public organizations endpoint#Why the list preloads icons and the detail does not]]
      org = Organization.find(params[:id])
      positions = org.organization_bill_positions.joins(:bill)
        .where(active: true)
        .map(&:to_public_json)

      props = {
        organization: org.to_public_json,
        organization_bill_positions: positions
      }

      # @lat: [[public-organizations-endpoint#What a signed-out reader is never sent]]
      if current_user
        follow = current_user
          .organization_follows
          .where(organization_id: org.id)
          .select(:id, :organization_id, :notification_cadence,
            :notify_on_new_position, :notify_on_support_change, :notify_on_summary_change)
          .first

        props[:current_user_follow_id] = follow&.id
        props[:user_follow_prefs] =
          follow ? {follow.organization_id => follow_prefs_payload(follow)} : {}
        props[:current_user_org_defaults] = org_defaults_payload(current_user)
        props[:is_member_of_org_ids] = current_user
          .user_organization_memberships
          .where(status: :active)
          .pluck(:organization_id)
      end

      render_inertia_or_json(
        page: Pages::ORGANIZATION,
        props: props
      )
    end

    private

    def follow_prefs_payload(follow)
      {
        follow_id: follow.id,
        notify_on_new_position: follow.notify_on_new_position,
        notify_on_support_change: follow.notify_on_support_change,
        notify_on_summary_change: follow.notify_on_summary_change,
        notification_cadence: follow.notification_cadence,
        muted: !follow.notify_on_new_position &&
          !follow.notify_on_support_change &&
          !follow.notify_on_summary_change
      }
    end

    def org_defaults_payload(user)
      {
        notify_on_new_position: user.notify_on_new_position_default,
        notify_on_support_change: user.notify_on_support_change_default,
        notify_on_summary_change: user.notify_on_summary_change_default,
        notification_cadence: user.org_position_cadence_default
      }
    end
  end
end
