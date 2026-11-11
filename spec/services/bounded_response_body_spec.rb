# frozen_string_literal: true

require "rails_helper"

# @lat: [[outbound-fetch-safety#An oversized download is stopped rather than refused afterwards]]
RSpec.describe BoundedResponseBody do
  describe "a body within the cap" do
    it "hands back exactly what it was given" do
      body = described_class.new(limit: 1_000)

      body.receive("abc", 3)
      body.receive("def", 6)

      expect(body.buffer).to eq("abcdef")
    end

    it "accepts a body that lands exactly on the cap" do
      body = described_class.new(limit: 6)

      body.receive("abc", 3)
      body.receive("def", 6)

      expect(body.buffer).to eq("abcdef")
    end
  end

  describe "a body over the cap" do
    # THE MEASUREMENT. A 10 MB response against a 1 MB cap: if the bound worked
    # the old way, all 10,240 chunks would be offered and 10 MB would be held.
    it "stops within one chunk of the cap instead of reading the whole response" do
      body = described_class.new(limit: 1024 * 1024)
      chunk = "x" * 1024
      offered = 0
      running = 0

      # The loop is written out rather than a helper: Steep resolves neither a
      # `def` in a describe block nor a constant beside one. Counts OUTSIDE the
      # raising call, since the count is the measurement.
      expect {
        while running < 10 * 1024 * 1024
          running += 1024
          offered += 1
          body.receive(chunk, running)
        end
      }.to raise_error(described_class::TooLarge)

      # One chunk past the cap is where it noticed, and nothing after that was
      # ever offered — the caller stops reading the socket.
      expect(offered).to eq(1025)
      expect(body.buffer.bytesize).to be <= 1024 * 1024
    end

    it "names the cap and how far it got, so an operator can tell a big file from a hostile one" do
      body = described_class.new(limit: 16, description: "tarball")

      expect { body.receive("x" * 20, 20) }
        .to raise_error(described_class::TooLarge, "tarball passed the 16-byte cap after 20 bytes")
    end
  end

  describe "bytes that are not the payload" do
    # A redirect's body is a courtesy page; failing an attachment because the
    # server put a large one in front would lose a document rather than
    # protect anything.
    it "holds none of them and refuses none of them, however many arrive" do
      body = described_class.new(limit: 1024)
      chunk = "x" * 1024
      offered = 0
      running = 0

      expect {
        while running < 10 * 1024 * 1024
          running += 1024
          offered += 1
          body.receive(chunk, running, keep: false)
        end
      }.not_to raise_error

      expect(offered).to eq(10 * 1024)
      expect(body.buffer).to eq("")
    end
  end

  describe "a retry that re-reads the response from the beginning" do
    # faraday-retry re-runs the whole request; Faraday's running total is
    # per attempt. Missing that, the buffer would mix both attempts' bytes
    # into a body that looks like success, not a refusal.
    it "starts again rather than appending the second attempt to the first" do
      body = described_class.new(limit: 1_000)

      body.receive("first attempt", 13)
      body.receive(" and more", 22)

      # The total goes backwards, which is the only signal a retry leaves here.
      body.receive("second attempt", 14)

      expect(body.buffer).to eq("second attempt")
    end

    # The cap is measured against the attempt, not against the two added up.
    it "does not count a retried attempt against the previous one" do
      body = described_class.new(limit: 20)

      body.receive("x" * 15, 15)

      expect { body.receive("y" * 15, 15) }.not_to raise_error
      expect(body.buffer).to eq("y" * 15)
    end
  end

  describe "elapsed time bounds" do
    # @lat: [[download-bounds#Download bounds]]
    it "raises TimeoutTooSlow as a StandardError subclass" do
      expect(described_class::TimeoutTooSlow).to be < StandardError
      expect(described_class::TimeoutTooSlow).not_to be < Timeout::Error
      expect(described_class::TimeoutTooSlow).not_to be < Faraday::Error if defined?(Faraday::Error)
    end

    it "raises TimeoutTooSlow when the monotonic clock exceeds the deadline" do
      deadline = 1_030.0
      body = described_class.new(limit: 1_000, deadline: deadline, max_elapsed: 30, description: "attachment")

      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(1_031.0)

      expect { body.receive("chunk", 5) }
        .to raise_error(described_class::TimeoutTooSlow, "attachment passed the 30-second ceiling")
    end

    it "enforces the deadline even when keep: false for courtesy redirect bodies" do
      deadline = 1_030.0
      body = described_class.new(limit: 1_000, deadline: deadline, max_elapsed: 30, description: "attachment")

      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(1_031.0)

      expect { body.receive("redirect chunk", 14, keep: false) }
        .to raise_error(described_class::TimeoutTooSlow, "attachment passed the 30-second ceiling")
    end

    it "does not raise when the clock is within the deadline" do
      deadline = 1_030.0
      body = described_class.new(limit: 1_000, deadline: deadline, max_elapsed: 30, description: "attachment")

      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(1_020.0)

      expect { body.receive("chunk", 5) }.not_to raise_error
      expect(body.buffer).to eq("chunk")
    end
  end
end
