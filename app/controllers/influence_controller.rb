# frozen_string_literal: true

class InfluenceController < ApplicationController
  def index
    u = current_user
    l = current_sway_locale
    if u.nil? || l.nil?
      redirect_to root_path
    elsif u.registered?
      render_inertia_or_json(
        page: Pages::INFLUENCE,
        props: {
          influence:
            InfluenceService
              .new(user: u, sway_locale: l)
              .to_builder
              .attributes!
              .except("isA?")
        }
      )
    else
      redirect_or_json(sway_registration_index_path)
    end
  end
end
