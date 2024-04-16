class HomeController < ApplicationController
  def index
    render inertia: 'Home', props: {
      name: 'Inertia Rails'
    }
  end
end
