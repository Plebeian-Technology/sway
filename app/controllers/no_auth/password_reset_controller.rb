class NoAuth::PasswordResetController < ApplicationController
  def index
    render inertia: 'PasswordReset', props: {
      name: 'Sway'
    }
  end
end
