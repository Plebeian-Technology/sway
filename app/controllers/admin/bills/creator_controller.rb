class Admin::Bills::CreatorController < ApplicationController
  before_action :verify_is_admin

  def index
    render inertia: "BillOfTheWeekCreator"
  end
end
