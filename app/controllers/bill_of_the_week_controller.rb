# frozen_string_literal: true

class BillOfTheWeekController < ApplicationController
  skip_before_action :authenticate_sway_user!, only: %i[index]

  def index
    b = Bill.of_the_week(sway_locale: current_sway_locale)
    b = b.first if b.is_a?(Array)

    if b.present?
      render_component(
        Pages::BILL_OF_THE_WEEK,
        -> do
          to_render = b.render(current_user, current_sway_locale)
          if params[:with]&.include?("legislator")
            to_render[:legislator] = current_user&.legislators(
              current_sway_locale,
            )&.first
          end
          to_render
        end,
      )
    else
      flash[
        :notice
      ] = "No Bill of the Week Available for #{current_sway_locale&.human_name}. Redirecting to Bills."
      redirect_to bills_path
    end
  end
end
