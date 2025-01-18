# frozen_string_literal: true
# typed: true

class InfluenceController < ApplicationController
  extend T::Sig

  def index
    u = current_user
    l = current_sway_locale
    if u.nil? || l.nil?
      redirect_to root_path
    elsif u.is_registration_complete
      render_component(Pages::INFLUENCE, {influence: InfluenceService.new(
        user: u,
        sway_locale: l
      ).to_builder.attributes!})
    else
      redirect_to sway_registration_index_path
    end
  end
end
