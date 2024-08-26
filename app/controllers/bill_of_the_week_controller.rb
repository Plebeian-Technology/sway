# frozen_string_literal: true
# typed: true

class BillOfTheWeekController < ApplicationController
  def index
    b = T.cast(Bill.where(sway_locale: current_sway_locale).of_the_week, T.nilable(T.any(Bill, T::Array[Bill])))
    b = b.first if b.is_a?(Array)

    if b.present?
      T.unsafe(self).render_bill_of_the_week(-> { b.render(current_user) })
    else
      redirect_to bills_path
    end
  end
end
