# frozen_string_literal: true

require_relative "../../db/seeds/models/sway_locale"
require_relative "../../db/seeds/models/legislator"
require_relative "../../db/seeds/models/bill"
require_relative "../../db/seeds/models/development_user_graph"

namespace :db do
  namespace :seed do
    desc "Re-seed locales, legislators, and bills unconditionally, bypassing the out-of-band edit " \
      "protection (last_seeded_at == updated_at equality check). " \
      "Bill re-seeding needs a local llama.cpp server for summaries; if it's unreachable, the bills " \
      "step is skipped with a warning and db:seed:bills:force can be re-run once it's up."
    task force: :environment do
      SwayLogging.info("db:seed:force — seeding locales + legislators + bills with force: true")
      locales = SeedSwayLocale.run(force: true)
      SeedLegislator.run(locales, force: true)

      begin
        SeedBill.run(locales, force: true)
      rescue SeedBill::ServiceUnreachableError,
        Faraday::ConnectionFailed,
        Errno::ECONNREFUSED => e
        SwayLogging.warn(
          "db:seed:force — SeedBill skipped: #{e.class}: #{e.message}. " \
          "Run bin/rails db:seed:bills:force separately if the issue clears."
        )
      end

      dev_seed_summary = SeedDevelopmentUserGraph.run(locales)
      unless dev_seed_summary.nil?
        SwayLogging.info(
          "db:seed:force development user graph seeded: #{dev_seed_summary}"
        )
      end

      SwayLogging.info("db:seed:force complete.")
    end
  end
end
