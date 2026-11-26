# frozen_string_literal: true

# @lat: [[organization-follows-controller-access-model#Write scope]]
class OrganizationFollowsController < ApplicationController
  before_action :set_follow, only: %i[destroy preferences]

  # @lat: [[organization-follows-controller-access-model#Why create is idempotent and combines follow + preferences]]
  def create
    org_id = params.require(:organization_id)
    follow = current_user.organization_follows
      .find_or_create_by!(organization_id: org_id) do |f|
        f.assign_attributes(OrganizationFollow.seed_attrs_from(current_user))
      end
    follow.update!(follow_prefs_params) if params.key?(:organization_follow)
    follow_success_response(follow)
  rescue ActiveRecord::RecordNotUnique
    # @lat: [[organization-follows-controller-access-model#Why create rescues RecordNotUnique]]
    follow = current_user.organization_follows.find_by!(organization_id: org_id)
    follow.update!(follow_prefs_params) if params.key?(:organization_follow)
    follow_success_response(follow)
  end

  def destroy
    @follow.destroy!
    redirect_or_json(
      back_or_organization_path(@follow.organization_id),
      flash_message: "Stopped tracking."
    )
  end

  def preferences
    @follow.update!(follow_prefs_params)
    redirect_or_json(back_or_organization_path(@follow.organization_id))
  end

  private

  def follow_success_response(follow)
    redirect_or_json(
      back_or_organization_path(follow.organization_id),
      flash_message: "Tracking #{follow.organization.name}!"
    )
  end

  # @lat: [[organization-follows-controller-access-model#Why the redirect target is the referring page, not always the detail page]]
  def back_or_organization_path(organization_id)
    url_from(request.referer) || public_organization_path(organization_id)
  end

  # @lat: [[organization-follows-controller-access-model#Write scope]]
  def set_follow
    @follow = current_user.organization_follows.find(params[:id])
  end

  def follow_prefs_params
    raw = params.require(:organization_follow).permit(
      :notification_cadence,
      :notify_on_new_position,
      :notify_on_support_change,
      :notify_on_summary_change
    )
    # @lat: [[org-notification-cascade-and-defaults#Why checkbox values are cast to real booleans before persisting]]
    %i[notify_on_new_position notify_on_support_change notify_on_summary_change].each do |key|
      raw[key] = ActiveModel::Type::Boolean.new.cast(raw[key]) if raw.key?(key)
    end
    raw
  end
end
