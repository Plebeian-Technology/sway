# typed: true

class LegislatorsController < ApplicationController
  before_action :redirect_if_no_current_user

  # GET /legislators or /legislators.json
  def index
    u = current_user
    if u
      if u.user_legislators.empty?
        redirect_to sway_registration_index_path
      else
        render inertia: 'Legislators', props: {
          user: u.to_builder.attributes!, legislators: u.user_legislators.map do |ul|
            T.cast(ul.legislator, Legislator).to_builder.attributes!
          end
        }
      end
    else
      redirect_to root_path
    end
  end

  # GET /legislators/1 or /legislators/1.json
  def show
  end

  private

  # Only allow a list of trusted parameters through.
  def legislator_params
    params.require(:legislator).permit(:id)
  end
end
