namespace :sway do
  # @lat: [[sway-google-cloud-storage#Sway Google Cloud Storage#How a destructive task refuses to be run by accident]]
  task assign_new_user_legislators: :environment do
    unless ENV["CONFIRM_ASSIGN_NEW_USER_LEGISLATORS"] == "1"
      abort("Refusing to run: set CONFIRM_ASSIGN_NEW_USER_LEGISLATORS=1 to deactivate and reassign all UserLegislators")
    end

    User.all.find_each do |user|
      user.user_legislators.update_all(active: false)
      user.sway_locales.each do |sway_locale|
        SwayLogging.info("assign_new_user_legislators.rake - Updating UserLegislators for User: #{user.id}, SwayLocale: #{sway_locale.name}")
        SwayRegistrationService.new(user, user.address, sway_locale, invited_by_id: nil).create_user_legislators
      rescue => e
        SwayLogging.error("assign_new_user_legislators.rake - failed for User #{user.id} / #{sway_locale.name}: #{e.class}: #{e.message}")
      end
    end
  end
end
