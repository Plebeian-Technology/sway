# frozen_string_literal: true

class RepresentativeReassignmentsController < ApplicationController
  before_action :authenticate_sway_user!

  def dismiss
    reassignment = current_user.representative_reassignments.find(params[:id])
    reassignment.dismiss!

    respond_to do |format|
      format.html { redirect_back_or_to(root_path) }
      format.json { head :no_content }
    end
  end

  private

  def authenticate_user!
    authenticate_sway_user!
  end
end
