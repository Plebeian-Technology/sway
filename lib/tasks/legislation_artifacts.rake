# frozen_string_literal: true

namespace :legislation do
  namespace :artifacts do
    desc "Copy the legislation artifact tree to the backup bucket. Optional: PREFIX="
    task backup: :environment do
      prefix = ENV["PREFIX"].presence || Legislation::ArtifactBackupService.default_prefix

      puts "Copying the legislation artifact tree to gs://<bucket>/#{prefix}"
      report = Legislation::ArtifactBackupService.new(prefix: prefix).call

      report.to_log_metadata.each { |key, value| puts "  #{key}: #{value}" }
      report.failed.each { |object_name, reason| puts "  FAILED #{object_name}: #{reason}" }

      abort("legislation:artifacts:backup finished #{report.status}") unless report.ok?
      puts "OK"
    end

    desc "Restore artifacts from the bucket. Required: DESTINATION=. Optional: ONLY=, PREFIX="
    task restore: :environment do
      destination = ENV["DESTINATION"].to_s
      abort("DESTINATION= is required. Name the directory to restore into; it is never guessed.") if destination.strip.empty?

      prefix = ENV["PREFIX"].presence || Legislation::ArtifactBackupService.default_prefix
      only = ENV["ONLY"].presence

      service = begin
        Legislation::ArtifactRestoreService.new(destination: destination, prefix: prefix, only: only)
      rescue Legislation::ArtifactRestoreService::LiveTreeRefused, ArgumentError => e
        abort(e.message)
      end

      puts "Restoring gs://<bucket>/#{service.effective_prefix} into #{service.destination}"
      report = service.call

      report.to_log_metadata.each { |key, value| puts "  #{key}: #{value}" }
      report.failed.each { |object_name, reason| puts "  FAILED #{object_name}: #{reason}" }

      abort("legislation:artifacts:restore finished #{report.status}") unless report.ok?
      puts "OK"
    end
  end
end
