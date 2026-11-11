# frozen_string_literal: true

namespace :sway do
  desc "Build the background-job database's tables if they are missing (safe to re-run)"
  task setup_queue_database: :environment do
    QueueDatabaseSetupService.new.call
  end
end
