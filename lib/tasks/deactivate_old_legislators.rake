namespace :sway do
  # Call like: ./bin/rake "sway:deactivate_old_legislators[[2024]]"

  desc "De-activates all Legislators that do not have an election_year within the passed array of election years."
  task :deactivate_old_legislators, [:election_years] => [:environment] do |task, args|
    election_years = JSON.parse(args[:election_years])

    Rails.logger.info("deactivate_old_legislators.rake - de-activate all Legislators in election years: #{election_years}")

    ids = Legislator.where(active: true).filter { |legislator| !election_years.include?(legislator.election_year) }.map(&:id)
    Legislator.where(id: ids).update_all(active: false)
  end
end
