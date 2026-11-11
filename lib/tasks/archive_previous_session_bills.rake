# frozen_string_literal: true

namespace :sway do
  namespace :bills do
    # @lat: [[archive-previous-session-bills#Archive bills after a session rollover]]
    desc "Preview older unfeatured bills for one locale; pass apply to archive them"
    task :archive_previous_sessions, [:locale, :mode] => :environment do |_task, args|
      raise ArgumentError, "A locale name is required" if args[:locale].blank?
      raise ArgumentError, "Mode must be preview or apply" unless args[:mode].nil? || %w[preview apply].include?(args[:mode])

      locale = SwayLocale.resolve_by_computed_name(args[:locale])
      raise ArgumentError, "Unknown locale: #{args[:locale]}" unless locale

      service = ArchivePreviousSessionBillsService.new(sway_locale: locale)
      session = service.current_session
      puts "Locale: #{locale.name}; current session: #{session.name} (#{session.start_date})"
      if args[:mode] == "apply"
        puts "Archived #{service.call} bills."
      else
        candidates = service.candidates
        puts "Preview: #{candidates.count} bills eligible for archiving."
        candidates.find_each do |bill|
          puts "#{bill.id}\t#{bill.external_id}\t#{bill.title}"
        end
      end
    end
  end
end
