# typed: true
class LegislatorVotesController < ApplicationController

  def index
    render json: current_user&.legislators(T.cast(current_sway_locale, SwayLocale)), status: :ok
  end

end
