# frozen_string_literal: true
# typed: true

class BillOfTheWeekController < ApplicationController
  def index
    b = T.cast(Bill.of_the_week(sway_locale: current_sway_locale), T.nilable(T.any(Bill, T::Array[Bill])))
    b = b.first if b.is_a?(Array)

    if b.present?
      render_component(Pages::BILL_OF_THE_WEEK, -> { b.render(current_user) })
    else
      redirect_to bills_path
    end
  end
end
