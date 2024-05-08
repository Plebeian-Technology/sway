class Admin::Bills::CreatorController < ApplicationController

  def index
    render inertia: "BillOfTheWeekCreator"
  end
end
