module RegisteredUserFixtures
  def complete_registration_with_active_link(user, legislator: nil)
    unless user.registered?
      legislator ||= FactoryBot.create(:legislator)
      FactoryBot.create(:user_legislator, user: user, legislator: legislator)
    end

    user.complete!
    user
  end
end

RSpec.configure do |config|
  config.include RegisteredUserFixtures
end
