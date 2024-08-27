# frozen_string_literal: true
# typed: true

class LegislatorsController < ApplicationController
  # GET /legislators or /legislators.json
  def index
    T.unsafe(self).render_legislators(
      lambda do
        {
          legislators: json_legislators
        }
      end
    )
  end

  # GET /legislators/1 or /legislators/1.json
  def show
  end

  private

  def json_legislators
    current_user&.user_legislators&.map do |ul|
      ul.legislator.to_builder.attributes!
    end
  end

  # Only allow a list of trusted parameters through.
  def legislator_params
    params.require(:legislator).permit(:id)
  end
end
