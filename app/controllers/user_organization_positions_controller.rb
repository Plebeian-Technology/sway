# frozen_string_literal: true
# typed: true

class UserOrganizationPositionsController < ApplicationController
    before_action :set_position, only: %i[update destroy]
    before_action :set_membership, only: %i[update destroy]
    before_action :current_user_must_be_member!

    # TODO: Create a position on a bill
    def create
        flash[:alert] = "Not implemented"
        redirect_to user_organization_membership_path(@membership)
    end

    def update
        change = find_unapproved_existing_or_new_change
        if change.approved?
            flash[:notice] = "Change to position has already been approved."
            redirect_to user_organization_membership_path(@membership) and return
        end

        if change.new_support == @position.support && change.new_summary == @position.summary
            flash[:notice] = "No changes to position detected."
            redirect_to user_organization_membership_path(@membership) and return
        end

        change.approved_by = nil

        if change.save
            flash[:notice] = "Created change to position subject to approval."
        else
            Rails.logger.error(@position.errors.full_messages)
            flash[:alert] = "Failed to save change to position."
        end
        redirect_to user_organization_membership_path(@membership)
    end

    def destroy
        if @membership.admin?
            @position.destroy!
            flash[:notice] = "Position for bill #{@position.bill.title} destroyed."
        else
            flash[:alert] = "Forbidden"
        end
        redirect_to user_organization_membership_path(@membership)
    end

    private

    def organization
        @organization ||= @position.organization
    end

    def set_position
        @position = OrganizationBillPosition.find(params[:id])
    end

    def set_membership
        @membership = UserOrganizationMembership.find_by(organization: organization, user: current_user)
    end

    def current_user_must_be_member!
        return if @membership.user_id == current_user&.id

        Rails.logger.info("Membership user_id #{@membership.user_id} does not match current_user.id #{current_user&.id}")
        flash[:alert] = "Forbidden"
        redirect_to root_path and return
    end

    def find_unapproved_existing_or_new_change
        existing_unapproved_change =
            OrganizationBillPositionChange.find_by(
                organization_bill_position: @position,
                updated_by: current_user,
                approved_by_id: nil,
            )
        if existing_unapproved_change
            existing_unapproved_change.new_support = params[:support]
            existing_unapproved_change.new_summary = params[:summary]
            return existing_unapproved_change
        end

        OrganizationBillPositionChange.new(
            organization_bill_position: @position,
            updated_by: current_user,
            previous_support: @position.support,
            previous_summary: @position.summary,
            new_support: params[:support],
            new_summary: params[:summary],
        )
    end
end
