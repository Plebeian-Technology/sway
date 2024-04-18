class NoAuth::RegistrationsController < ApplicationController
  def create
    user = User.where({ email: new_user_params.fetch(:email) })

    user = if !user
             User.create(new_user_params)
           else
             user[0]
           end

    if user.valid?
      res = HTTParty.post("#{ENV['BITWARDEN_PASSWORDLESS_API_URL']}/register/token",
                          body: JSON.generate({
                                                userId: user.id,
                                                username: user.email
                                              }),
                          headers: {
                            'ApiSecret' => ENV['BITWARDEN_PASSWORDLESS_API_PRIVATE_KEY'],
                            'Content-Type' => 'application/json'
                          })

      render json: JSON.parse(res.body)
    else
      render json: user.errors
    end
  end

  def new
    render inertia: 'SignupPasskey', props: {
      name: 'Sway'
    }
  end

  private

  def new_user_params
    params.require(:registration).permit(:email)
  end
end
