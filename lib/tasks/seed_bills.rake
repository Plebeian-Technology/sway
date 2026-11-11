# frozen_string_literal: true

require_relative "../../db/seeds/models/bill"
require_relative "../../db/seeds/models/development_user_graph"
require_relative "../../db/seeds/seed_log"

namespace :db do
  namespace :seed do
    desc "Seed Baltimore bills via the Rails-native legislation pipeline " \
      "(RunLegislationPipelineJob.perform_now). Skips if bills already exist."
    task bills: :environment do
      SeedBillRunner.call(force: false, refresh: false)
    end

    namespace :bills do
      desc "Reseed bills even if Baltimore already has some. Reuses the on-disk cache."
      task force: :environment do
        SeedBillRunner.call(force: true, refresh: false)
      end

      desc "Force pipeline to re-fetch upstream data (Legistar API + hearing PDFs) before seeding."
      task refresh: :environment do
        SeedBillRunner.call(force: true, refresh: true)
      end
    end
  end
end

class SeedBillRunner
  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Seeding fails loudly when a pipeline run does not succeed]]
  class NoLocaleError < StandardError; end

  def self.call(force:, refresh:)
    SeedLog.say(
      "→ Seeding Baltimore bills via the legislation pipeline (force=#{force} refresh=#{refresh}). " \
      "This is network-heavy — Legistar API + hearing PDFs + LLM bill summaries " \
      "(local llama.cpp on :8888 in dev) — and can take several minutes…"
    )

    locales = SwayLocale.where(city: "baltimore", state: "maryland").to_a
    if locales.empty?
      raise NoLocaleError,
        "No Baltimore sway_locale in DB. Run `bin/rails db:seed` first."
    end

    result = SeedBill.run(locales, force: force, refresh: refresh)
    dev_seed_summary = SeedDevelopmentUserGraph.run(locales)

    if result.nil?
      SeedLog.say("✓ db:seed:bills finished — no bills seeded (skipped or failed; see logs).")
    else
      SeedLog.say("✓ db:seed:bills finished. Seeded #{result.length} bills: #{result.join(", ")}")
    end

    return if dev_seed_summary.nil?

    SeedLog.say("✓ db:seed:bills development user graph seeded: #{dev_seed_summary}")
  end
end
