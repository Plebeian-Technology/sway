# frozen_string_literal: true

require "open3"

module Sway
  # @lat: [[subprocess-bounded-execution#How .argv closes the gap]]
  module Subprocess
    # @lat: [[subprocess-output-capping#Why OutputTooLarge carries stderr]]
    class TimedOut < StandardError
    end

    # @lat: [[subprocess-output-capping#Why the two pipes are drained concurrently]]
    class OutputTooLarge < StandardError
      attr_reader :stderr

      def initialize(message, stderr: "")
        super(message)
        @stderr = stderr
      end
    end

    # @lat: [[subprocess-output-capping#Why the two pipes are drained concurrently]]
    MAX_STDOUT_BYTES = 16 * 1024 * 1024

    # @lat: [[subprocess-output-capping#Why output needs a cap at all]]
    MAX_STDERR_BYTES = 256 * 1024

    CHUNK_BYTES = 64 * 1024

    # @lat: [[subprocess-deadline-design#Why the deadline has to cover draining, not just child exit]]
    DEFAULT_TIMEOUT_SECONDS = 300

    TERM_GRACE_SECONDS = 5

    GROUP_POLL_SECONDS = 0.05

    # @lat: [[subprocess-deadline-design#Why the deadline has to cover draining, not just child exit]]
    DRAIN_FLOOR_SECONDS = 0.25

    def self.capture3(
      *command,
      timeout_seconds: DEFAULT_TIMEOUT_SECONDS,
      max_stdout_bytes: MAX_STDOUT_BYTES,
      max_stderr_bytes: MAX_STDERR_BYTES
    )
      # @lat: [[subprocess-deadline-design#Why the deadline has to cover draining, not just child exit]]
      stdin, stdout, stderr, wait_thr = Open3.popen3(*argv(command), pgroup: true)
      begin
        stdin.close
        drain_within(
          command, stdout, stderr, wait_thr,
          timeout_seconds: timeout_seconds, max_stdout_bytes: max_stdout_bytes, max_stderr_bytes: max_stderr_bytes
        )
      ensure
        [stdin, stdout, stderr].each { |io| io.close unless io.closed? }
      end
    end

    # @lat: [[subprocess-deadline-design#Why .drain_within is split out from .capture3]]
    def self.drain_within(command, stdout, stderr, wait_thr, timeout_seconds:, max_stdout_bytes:, max_stderr_bytes:)
      # @lat: [[subprocess-output-capping#Why the two pipes are drained concurrently]]
      pid = wait_thr.pid
      out_reader = Thread.new { drain(stdout, max_stdout_bytes) { signal_group("KILL", pid) } }
      err_reader = Thread.new { drain(stderr, max_stderr_bytes) { signal_group("KILL", pid) } }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

      if wait_thr.join(remaining(deadline)).nil?
        abandon(wait_thr, out_reader, err_reader)
        raise TimedOut, "#{command.first} exceeded #{timeout_seconds}s and was killed"
      end

      # @lat: [[subprocess-deadline-design#Why the deadline has to cover draining, not just child exit]]
      if out_reader.join(drain_join_limit(deadline)).nil? ||
          err_reader.join(drain_join_limit(deadline)).nil?
        abandon(wait_thr, out_reader, err_reader)
        raise TimedOut, "#{command.first} exceeded #{timeout_seconds}s draining output and was killed"
      end

      out, out_overflowed = out_reader.value #: [String, bool]
      err, err_overflowed = err_reader.value #: [String, bool]

      if out_overflowed || err_overflowed
        stream = out_overflowed ? "stdout" : "stderr"
        limit = out_overflowed ? max_stdout_bytes : max_stderr_bytes
        # @lat: [[subprocess-output-capping#Why OutputTooLarge carries stderr]]
        raise OutputTooLarge.new(
          "#{command.first} produced more than #{limit} bytes on #{stream} and was killed",
          stderr: err
        )
      end

      [out, err, wait_thr.value]
    end

    # @lat: [[subprocess-output-capping#Why output needs a cap at all]]
    def self.drain(io, limit)
      buffer = +"".b
      overflowed = false

      # @lat: [[subprocess-output-capping#How .drain decides a stream overflowed]]
      begin
        while (chunk = io.read(CHUNK_BYTES))
          buffer << chunk
          if buffer.bytesize > limit
            overflowed = true
            break
          end
        end
      rescue IOError
        nil
      end

      yield if overflowed && block_given?
      [reencode(buffer, io), overflowed]
    end

    # @lat: [[subprocess-output-capping#Why .reencode puts the external encoding back]]
    def self.reencode(buffer, io)
      buffer.force_encoding(io.external_encoding || Encoding.default_external)
    end

    # @lat: [[subprocess-bounded-execution#How .argv closes the gap]]
    def self.argv(command)
      raise ArgumentError, "pass argv, not a shell string: the command is empty" if command.empty?
      return command unless command.length == 1 && command.first.is_a?(::String)

      binary = command.first.to_s
      [[binary, binary]]
    end

    def self.remaining(deadline)
      [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.0].max
    end

    def self.drain_join_limit(deadline)
      [remaining(deadline), DRAIN_FLOOR_SECONDS].max
    end

    # @lat: [[subprocess-termination-and-pid-reuse#Why both waits are bounded]]
    def self.abandon(wait_thr, out_reader, err_reader)
      terminate(wait_thr)
      out_reader.kill
      err_reader.kill
    end

    # @lat: [[subprocess-termination-and-pid-reuse#Why TERM first, then KILL]]
    def self.terminate(wait_thr)
      signal_group("TERM", wait_thr.pid)
      await_group_exit(wait_thr, TERM_GRACE_SECONDS)
      signal_group("KILL", wait_thr.pid)
      return unless wait_thr.join(TERM_GRACE_SECONDS).nil?

      SwayLogging.warn("sway.subprocess.unreaped_child", pid: wait_thr.pid)
      nil
    end

    # @lat: [[subprocess-termination-and-pid-reuse#Why .await_group_exit polls instead of sleeping the full grace period]]
    def self.await_group_exit(wait_thr, seconds)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      wait_thr.join(seconds)
      sleep(GROUP_POLL_SECONDS) while group_alive?(wait_thr.pid) && remaining(deadline).positive?
      nil
    end

    # @lat: [[subprocess-termination-and-pid-reuse#Why group_alive? treats EPERM as alive]]
    def self.group_alive?(pid)
      Process.kill(0, -pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    # @lat: [[subprocess-termination-and-pid-reuse#Why TERM first, then KILL]]
    def self.signal_group(name, pid)
      return unless group_alive?(pid)

      Process.kill(name, -pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
  end
end
