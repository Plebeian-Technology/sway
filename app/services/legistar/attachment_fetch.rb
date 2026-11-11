# frozen_string_literal: true

require "uri"

module Legistar
  # @lat: [[outbound-fetch-safety#Every redirect hop is checked before it is followed]]
  class AttachmentFetch
    class Rejected < StandardError
    end

    class TooLarge < Rejected
    end

    class TooSlow < Rejected
    end

    # @lat: [[outbound-fetch-safety#Every redirect hop is checked before it is followed]]
    MAX_REDIRECTS = 3

    REDIRECT_STATUSES = (300..399)

    # @lat: [[download-bounds#Download bounds]]
    MAX_ATTACHMENT_BYTES = 32 * 1024 * 1024
    MAX_ELAPSED_SECONDS = 30

    def initialize(connection:, max_elapsed: MAX_ELAPSED_SECONDS)
      @connection = connection
      @max_elapsed = max_elapsed
    end

    def call(url)
      # @lat: [[outbound-fetch-safety#Every redirect hop is checked before it is followed]]
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @max_elapsed
      current = AttachmentUrl.normalize(url)
      reject_disallowed!(current)

      (MAX_REDIRECTS + 1).times do
        check_deadline!(deadline)
        response = get_bounded(current, deadline: deadline)
        check_deadline!(deadline)

        unless REDIRECT_STATUSES.cover?(response.status)
          enforce_advertised_size!(response)
          return response
        end

        current = next_hop(current, response)
      end

      raise Rejected, "too many redirects (limit #{MAX_REDIRECTS})"
    rescue URI::Error => e
      # @lat: [[outbound-fetch-safety#Every redirect hop is checked before it is followed]]
      raise Rejected, "url could not be requested: #{e.class.name.demodulize}"
    end

    private

    # @lat: [[download-bounds#Download bounds]]
    def get_bounded(url, deadline:)
      body = BoundedResponseBody.new(
        limit: MAX_ATTACHMENT_BYTES,
        deadline: deadline,
        max_elapsed: @max_elapsed,
        description: "attachment"
      )

      response = @connection.get(url) do |request|
        request.options.on_data = proc do |chunk, overall_received_bytes, env|
          body.receive(chunk, overall_received_bytes, keep: !REDIRECT_STATUSES.cover?(env.status.to_i))
        end
      end

      response.env.body = body.buffer
      response
    rescue BoundedResponseBody::TooLarge => e
      raise TooLarge, e.message
    rescue BoundedResponseBody::TimeoutTooSlow => e
      raise TooSlow, e.message
    end

    def check_deadline!(deadline)
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise TooSlow, "attachment download exceeded #{@max_elapsed}-second ceiling"
      end
    end

    # @lat: [[outbound-fetch-safety#A declared size is checked as well as the bytes that arrive]]
    def enforce_advertised_size!(response)
      advertised = response.headers["content-length"].to_s
      return unless advertised.match?(/\A\d+\z/) && advertised.to_i > MAX_ATTACHMENT_BYTES

      raise TooLarge, "response advertises #{advertised} bytes, over the #{MAX_ATTACHMENT_BYTES}-byte cap"
    end

    def reject_disallowed!(url)
      reason = Legistar::AttachmentUrl.rejection_reason(url)
      raise Rejected, reason if reason
    end

    def next_hop(current, response)
      location = AttachmentUrl.normalize(response.headers["location"])
      raise Rejected, "HTTP #{response.status} with no Location header" if location.empty?

      target = absolute_target(current, location, response.status)
      reject_disallowed!(target)
      target
    end

    # @lat: [[outbound-fetch-safety#Every redirect hop is checked before it is followed]]
    def absolute_target(current, location, status)
      URI.join(current, location).to_s
    rescue URI::Error, ArgumentError
      raise Rejected, "HTTP #{status} Location is not a resolvable url"
    end
  end
end
