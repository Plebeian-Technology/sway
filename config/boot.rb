ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# @lat: [[new-relic-license-key-boot-normalization#Why this credential skips EnvSecret]]
if ENV.key?("NEW_RELIC_LICENSE_KEY")
  normalized_new_relic_key = ENV["NEW_RELIC_LICENSE_KEY"].to_s.strip
  if normalized_new_relic_key.empty?
    ENV.delete("NEW_RELIC_LICENSE_KEY")
  else
    ENV["NEW_RELIC_LICENSE_KEY"] = normalized_new_relic_key
  end
end

# @lat: [[host-boot-guard-docker-storage#Why Rails refuses to boot on the host]]
unless ENV["IS_DOCKER"].to_s.match?(/\A(1|true)\z/i) ||
    ENV["RAILS_ENV"].to_s == "production" ||
    !ENV["SWAY_ALLOW_HOST_RAILS"].to_s.empty?
  # rubocop:disable Rails/Exit
  abort <<~MSG
    Refusing to boot Rails on the host (RAILS_ENV=#{ENV["RAILS_ENV"].to_s.empty? ? "<unset, defaults to development>" : ENV["RAILS_ENV"]}).
    Dev/test SQLite databases live in the `sway_storage` Docker named volume.
    Use dip:
      dip run rails <command>      # one-off rails task (db:seed, db:migrate, ...)
      dip run rails s              # rails server
      dip run rspec                # backend tests
    To bypass intentionally (rare), set SWAY_ALLOW_HOST_RAILS=1.
  MSG
  # rubocop:enable Rails/Exit
end

require "bundler/setup"
require "bootsnap/setup"
