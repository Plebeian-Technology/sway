# typed: true
# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    Rails.logger.info 'Render Home.tsx'

    render inertia: 'Home', props: {
      name: 'Sway'
    }
  end
end
