# frozen_string_literal: true
# typed: true

class BillOfTheWeekController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[index]

  def index
    b = T.cast(Bill.of_the_week(sway_locale: current_sway_locale), T.nilable(T.any(Bill, T::Array[Bill])))
    b = b.first if b.is_a?(Array)

    if b.present?
      render_component(Pages::BILL_OF_THE_WEEK, -> {
        to_render = b.render(current_user, current_sway_locale)
        if params[:with]&.include?("legislator")
          to_render[:legislator] = current_user&.legislators(current_sway_locale)&.first
        end
        to_render
      })
    else
      flash[:notice] = "No Bill of the Week Available for #{current_sway_locale&.name}. Redirecting to Bills."
      redirect_to bills_path
    end
  end
end
