# frozen_string_literal: true

class HomeController < ApplicationController
  skip_before_action :authenticate_sway_user!

  def index
    u = current_user
    if u.nil?
      # @lat: [[shared-error-params#Raw error parameters never reach shared page props]]
      render inertia: Pages::HOME,
        props: {
          name: "Sway",
          isBubbles: true
        }
    elsif u.registered?
      redirect_to feed_path
    else
      redirect_to sway_registration_index_path
    end
  end
end
