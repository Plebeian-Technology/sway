# frozen_string_literal: true

# SeedLog.say writes a milestone to both the terminal (stdout) and the Rails log.
# @lat: [[seed-log-terminal-visibility#Why SeedLog writes to stdout, not just Rails.logger]]
module SeedLog
  def self.say(message)
    unless Rails.env.test?
      $stdout.puts(message)
      $stdout.flush
    end
    Rails.logger.info(message)
  end
end
