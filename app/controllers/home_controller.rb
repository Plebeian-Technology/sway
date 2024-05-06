# typed: true
# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    u = current_user
    if u.nil?
      T.unsafe(self).render_home({name: 'Sway', isBubbles: true})
    elsif u.is_registration_complete
      redirect_to legislators_path
    else
      redirect_to sway_registration_index_path
    end
  end
end
