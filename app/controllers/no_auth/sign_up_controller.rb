class NoAuth::SignUpController < ApplicationController
  def index
    render inertia: 'SignUp', props: {
      name: 'Sway'
    }
  end
end
