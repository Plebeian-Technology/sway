# frozen_string_literal: true

# @lat: [[outbound-fetch-safety#An oversized download is stopped rather than refused afterwards]]
class BoundedResponseBody
  # @lat: [[download-bounds#Download bounds]]
  class TooLarge < StandardError
  end

  class TimeoutTooSlow < StandardError
  end

  def initialize(limit:, deadline: nil, max_elapsed: nil, description: "response body")
    @limit = limit
    @deadline = deadline
    @max_elapsed = max_elapsed
    @description = description
    @received = 0
    @buffer = +""
  end

  attr_reader :buffer

  def receive(chunk, overall_received_bytes, keep: true)
    restart if overall_received_bytes <= @received
    @received = overall_received_bytes

    deadline = @deadline
    if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      raise TimeoutTooSlow, "#{@description} passed the #{@max_elapsed || "elapsed"}-second ceiling"
    end

    return unless keep

    if @received > @limit
      raise TooLarge, "#{@description} passed the #{@limit}-byte cap after #{@received} bytes"
    end

    @buffer << chunk
  end

  private

  def restart
    @received = 0
    @buffer = +""
  end
end
