class InfluenceController < ApplicationController
  def index
    u = current_user
    if u.nil?
      redirect_to root_path
    elsif u.is_registration_complete
      T.unsafe(self).render_influence
    else
      redirect_to sway_registration_index_path
    end
  end
end
