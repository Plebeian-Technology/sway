namespace :sway do
  desc "De-activates all UserLegislators and assigns new ones to each user. Run after each election."
  task assign_new_user_legislators: :environment do
    Rails.logger.info("assign_new_user_legislators.rake - de-activate all UserLegislators")
    UserLegislator.update_all(active: false)

    User.all.each do |user|
      user.sway_locales.each do |sway_locale|
        Rails.logger.info("assign_new_user_legislators.rake - Updating UserLegislators for User: #{user.id}, SwayLocale: #{sway_locale.name}")
        SwayRegistrationService.new(user, user.address, sway_locale, invited_by_id: nil).create_user_legislators
      end
    end
  end
end
