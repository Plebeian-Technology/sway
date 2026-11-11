# frozen_string_literal: true

module Sway
  # @lat: [[boot-time-backfills#Only the web server process enqueues]]
  module BootEnqueue
    class << self
      def web_server_process?
        defined?(Rails::Server) ? true : false
      end
    end
  end
end
