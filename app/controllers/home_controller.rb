class HomeController < ApplicationController
  def index
    render inertia: 'Home', props: {
      name: 'Sway'
    }
    # y
  end
end
