class RecaptchaUtil
  RECAPTCHA_URL = 'https://www.google.com/recaptcha/api/siteverify'

  def self.valid?(token)
    return true if Rails.env.test?

    Faraday.post(RECAPTCHA_URL, {
      body: "secret=#{ENV['GOOGLE_RECAPTCHA_SECRET_KEY']}&response=#{token}",
      headers: {
        'Content-Type' => 'application/x-www-form-urlencoded',
        'Charset' => 'utf-8',
        'Accept' => 'application/json'
      }
    }).fetch('success', false)
  end
end
