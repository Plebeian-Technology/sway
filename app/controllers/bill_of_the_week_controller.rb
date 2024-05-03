# typed: true

class BillOfTheWeekController < ApplicationController
  before_action :redirect_if_no_current_user

  def index
    b = T.cast(Bill.where(sway_locale: current_sway_locale).of_the_week, T.nilable(T.any(Bill, T::Array[Bill])))
    b = b.first if b.is_a?(Array)

    if b.present?
      T.unsafe(self).render_bill_of_the_week({
        bill: b.to_builder.attributes!
      })
    else
      redirect_to legislators_path
    end
  end
end
