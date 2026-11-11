# frozen_string_literal: true

require "rails_helper"
require "timeout"

# @lat: [[steep-typed-spec-helpers#let and def inside a describe block]]
module SubprocessSpecHelpers
  # Models a child stuck in an uninterruptible sleep -- see
  # docs/explanation/subprocess-termination-and-pid-reuse.md.
  # @lat: [[steep-typed-spec-helpers#let and def inside a describe block#Accepting the gap with steep:ignore instead of moving the helper out]]
  class UnreapableWaiter
    attr_reader :pid

    def initialize(pid)
      @pid = pid
    end

    def join(limit = nil)
      limit.nil? ? sleep : nil
    end
  end

  # A fake wait thread that has ALREADY finished — the drain-timeout case, where
  # the direct child exited and one of ITS children still holds the pipe open.
  class ExitedWaiter
    attr_reader :pid

    def initialize(pid)
      @pid = pid
    end

    def join(_limit = nil)
      self
    end
  end

  # A fake wait thread that has finished AND has an exit status to hand back —
  # where .drain_within stands once the child has exited and the only work left
  # is reading what already sits in the pipes.
  class CompletedWaiter
    attr_reader :pid
    attr_reader :value

    def initialize(pid, value)
      @pid = pid
      @value = value
    end

    def join(_limit = nil)
      self
    end
  end

  # A process id whose process and process group are both definitely gone, so
  # .signal_group does nothing (the kernel answers ESRCH) instead of hitting some
  # unrelated process.
  def self.reaped_pid
    pid = Process.spawn("true", pgroup: true)
    Process.waitpid(pid)
    pid
  end

  # A real Process::Status from a command that succeeded, for the fakes standing
  # in for a wait thread whose child has already exited.
  def self.reaped_status
    Process.waitpid2(Process.spawn("true", pgroup: true))[1]
  end
end

# @lat: [[subprocess-bounded-execution#The problem: Open3.capture3 waits forever]]
RSpec.describe Sway::Subprocess do
  describe ".capture3" do
    it "returns stdout, stderr and the status for a normal command" do
      stdout, stderr, status = described_class.capture3("sh", "-c", "printf out; printf err 1>&2")

      expect(stdout).to eq("out")
      expect(stderr).to eq("err")
      expect(status).to be_success
    end

    it "reports a non-zero exit through the status rather than raising" do
      _stdout, _stderr, status = described_class.capture3("sh", "-c", "exit 3")

      expect(status).not_to be_success
      expect(status.exitstatus).to eq(3)
    end

    it "kills a command that outruns its timeout and raises TimedOut" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { described_class.capture3("sleep", "30", timeout_seconds: 0.3) }
        .to raise_error(described_class::TimedOut, /sleep/)

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      expect(elapsed).to be < 15
    end

    it "passes positional args through without a shell, so a hostile filename cannot inject" do
      stdout, _stderr, status = described_class.capture3("echo", "; rm -rf /")

      expect(status).to be_success
      expect(stdout.strip).to eq("; rm -rf /")
    end

    it "raises the same SystemCallError Open3.capture3 does when the binary is absent" do
      expect { described_class.capture3("sway-no-such-binary-#{SecureRandom.hex(4)}") }
        .to raise_error(SystemCallError)
    end

    # @lat: [[subprocess-bounded-execution#How .argv closes the gap]]
    # No caller today passes a single element, but this module exists to be the
    # one doorway every future subprocess goes through, and the next caller will
    # take those docs at their word.
    it "never routes a single-element command through a shell" do
      probe = Rails.root.join("tmp", "sway_shell_probe_#{SecureRandom.hex(6)}.txt")
      begin
        FileUtils.rm_f(probe)

        expect {
          described_class.capture3("echo shellcheck > #{probe}; echo INJECTED")
        }.to raise_error(SystemCallError)

        expect(File.exist?(probe)).to be(false)
      ensure
        FileUtils.rm_f(probe)
      end
    end

    it "still runs a legitimate zero-argument binary given as one element" do
      stdout, _stderr, status = described_class.capture3("true")

      expect(status).to be_success
      expect(stdout).to eq("")
    end

    it "rejects an empty command rather than handing it to Open3" do
      expect { described_class.capture3 }.to raise_error(ArgumentError, /argv/)
    end

    # @lat: [[subprocess-deadline-design#Why the deadline has to cover draining, not just child exit]]
    it "enforces the deadline on total wall clock, not just on child exit" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { described_class.capture3("sh", "-c", "sleep 30 & exit 0", timeout_seconds: 0.5) }
        .to raise_error(described_class::TimedOut, /draining/)

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      expect(elapsed).to be < 20
    end

    # @lat: [[subprocess-output-capping#Why output needs a cap at all]]
    describe "output size bounds" do
      it "kills the child and raises OutputTooLarge when stdout outruns its cap" do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect {
          described_class.capture3("sh", "-c", "yes sway | head -c 40000000", max_stdout_bytes: 1024)
        }.to raise_error(described_class::OutputTooLarge, /stdout/)

        # It raises on the size limit, not by letting the clock run out.
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        expect(elapsed).to be < 20
      end

      # @lat: [[subprocess-output-capping#Why output needs a cap at all]]
      it "kills the child and raises OutputTooLarge when stderr outruns its cap" do
        expect {
          described_class.capture3("sh", "-c", "yes sway | head -c 40000000 >&2", max_stderr_bytes: 1024)
        }.to raise_error(described_class::OutputTooLarge, /stderr/)
      end

      # @lat: [[subprocess-output-capping#Why output needs a cap at all]]
      it "hands the bounded stderr to the caller when the stderr cap trips" do
        expect {
          described_class.capture3(
            "sh", "-c", "printf 'unsupported error: OCR Disabled in this build\n' >&2; yes sway | head -c 400000 >&2",
            max_stderr_bytes: 1024
          )
        }.to raise_error(described_class::OutputTooLarge) { |error|
          expect(error.stderr).to include("OCR Disabled in this build")
        }
      end

      it "carries an empty stderr rather than nil when it is stdout that overflowed" do
        expect {
          described_class.capture3("sh", "-c", "yes sway | head -c 400000", max_stdout_bytes: 1024)
        }.to raise_error(described_class::OutputTooLarge) { |error|
          expect(error.stderr).to eq("")
        }
      end

      it "holds a bounded buffer rather than the whole stream" do
        # 8 MiB of stdout against a 64 KiB cap. If the reader still read to the
        # end first, all 8 MiB would sit in memory before anything checked.
        expect {
          described_class.capture3("sh", "-c", "yes sway | head -c 8388608", max_stdout_bytes: 65_536)
        }.to raise_error(described_class::OutputTooLarge)
      end

      it "returns output that exactly fills the cap without calling it an overflow" do
        stdout, _stderr, status = described_class.capture3(
          "sh", "-c", "yes sway | head -c 1024", max_stdout_bytes: 1024
        )

        expect(stdout.bytesize).to eq(1024)
        expect(status).to be_success
      end

      it "defaults to a cap on both streams rather than to unbounded reads" do
        expect(described_class::MAX_STDOUT_BYTES).to be_a(Integer)
        expect(described_class::MAX_STDERR_BYTES).to be_a(Integer)
        expect(described_class::MAX_STDERR_BYTES).to be < described_class::MAX_STDOUT_BYTES
      end

      it "leaves ordinary small output untouched" do
        stdout, stderr, status = described_class.capture3("sh", "-c", "printf out; printf err 1>&2")

        expect(stdout).to eq("out")
        expect(stderr).to eq("err")
        expect(status).to be_success
      end
    end

    it "signals the whole process group, so a forked descendant does not outlive the deadline" do
      marker = Rails.root.join("tmp", "sway_pgroup_probe_#{SecureRandom.hex(6)}.txt")
      begin
        FileUtils.rm_f(marker)

        expect {
          described_class.capture3("sh", "-c", "(sleep 3; echo alive > #{marker}) & exit 0", timeout_seconds: 0.3)
        }.to raise_error(described_class::TimedOut)

        # The grandchild gets TERM along with its group, so it never reaches its write.
        sleep 4
        expect(File.exist?(marker)).to be(false)
      ensure
        FileUtils.rm_f(marker)
      end
    end

    # @lat: [[subprocess-deadline-design#Why the "child will not die" spec fakes the signal rather than spawning an uninterruptible one]]
    it "returns within its own bound when the child will not die" do
      allow(described_class).to receive(:signal_group)
      stub_const("#{described_class}::TERM_GRACE_SECONDS", 0.2)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect {
        described_class.capture3("sh", "-c", "sleep 6", timeout_seconds: 0.2)
      }.to raise_error(described_class::TimedOut)

      # A loose bound: two grace periods plus slack, and still far short of the
      # child's 6-second life. The claim is "limited by OUR budget, not by the
      # child's", so the wide margin does not weaken it.
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
    end

    # @lat: [[subprocess-deadline-design#Why a separate spec proves the child is abandoned, not just that the timing bound holds]]
    it "leaves the unreapable child running rather than waiting it out" do
      child_pid = nil #: Integer?
      begin
        allow(described_class).to receive(:signal_group) { |_name, pid| child_pid = pid }
        stub_const("#{described_class}::TERM_GRACE_SECONDS", 0.2)

        expect {
          described_class.capture3("sh", "-c", "sleep 6", timeout_seconds: 0.2)
        }.to raise_error(described_class::TimedOut)

        expect(child_pid).not_to be_nil
        expect { Process.kill(0, child_pid.to_i) }.not_to raise_error
      ensure
        Process.kill("KILL", child_pid.to_i) if child_pid
      end
    end
  end

  # @lat: [[subprocess-termination-and-pid-reuse#Why both waits are bounded]]
  describe ".terminate" do
    it "bounds the final reap, so a child that will not die cannot block the caller forever" do
      waiter = SubprocessSpecHelpers::UnreapableWaiter.new(SubprocessSpecHelpers.reaped_pid)

      expect { Timeout.timeout(2) { described_class.terminate(waiter) } }.not_to raise_error
    end

    it "logs the unreaped child rather than waiting on it" do
      waiter = SubprocessSpecHelpers::UnreapableWaiter.new(SubprocessSpecHelpers.reaped_pid)
      allow(SwayLogging).to receive(:warn)

      Timeout.timeout(2) { described_class.terminate(waiter) }

      expect(SwayLogging).to have_received(:warn)
        .with("sway.subprocess.unreaped_child", hash_including(pid: waiter.pid))
    end

    # @lat: [[subprocess-termination-and-pid-reuse#Why .await_group_exit polls instead of sleeping the full grace period]]
    it "gives descendants a real grace period when the direct child has already exited" do
      stub_const("#{described_class}::TERM_GRACE_SECONDS", 0.4)
      ready = Rails.root.join("tmp", "sway_term_grace_#{SecureRandom.hex(6)}")
      FileUtils.rm_f(ready)
      pid = Process.spawn("sh", "-c", "trap '' TERM; : > #{ready}; sleep 5", pgroup: true)
      reaper = Process.detach(pid)
      begin
        spawn_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.01 until File.exist?(ready) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > spawn_deadline
        expect(File.exist?(ready)).to be(true)
        signalled = [] #: Array[[String, Float]]
        allow(described_class).to receive(:signal_group).and_wrap_original do |original, name, group_pid|
          signalled << [name, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
          original.call(name, group_pid)
        end

        described_class.terminate(SubprocessSpecHelpers::ExitedWaiter.new(pid))

        expect(signalled.map(&:first)).to eq(%w[TERM KILL])
        expect(signalled[1][1] - signalled[0][1]).to be >= 0.3
      ensure
        begin
          Process.kill("KILL", -pid)
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end
        reaper.join(2)
        FileUtils.rm_f(ready)
      end
    end

    it "does not burn the grace period when nothing is left in the group" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      described_class.terminate(SubprocessSpecHelpers::ExitedWaiter.new(SubprocessSpecHelpers.reaped_pid))

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    end

    # @lat: [[subprocess-termination-and-pid-reuse#The pid-reuse race]]
    # Every example here builds that exact state on purpose --
    # SubprocessSpecHelpers.reaped_pid spawns a process, waits for it, and hands
    # back the freed id -- and then leans on the kernel's ESRCH answer to keep it
    # harmless.
    it "delivers no signal to a process group that has already drained" do
      pid = SubprocessSpecHelpers.reaped_pid
      allow(Process).to receive(:kill).and_call_original

      described_class.terminate(SubprocessSpecHelpers::ExitedWaiter.new(pid))

      expect(Process).not_to have_received(:kill).with("TERM", -pid)
      expect(Process).not_to have_received(:kill).with("KILL", -pid)
    end

    it "still signals a group that is genuinely alive" do
      ready = Rails.root.join("tmp", "sway_alive_group_#{SecureRandom.hex(6)}")
      FileUtils.rm_f(ready)
      pid = Process.spawn("sh", "-c", "trap '' TERM; : > #{ready}; sleep 5", pgroup: true)
      reaper = Process.detach(pid)
      begin
        spawn_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.01 until File.exist?(ready) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > spawn_deadline
        stub_const("#{described_class}::TERM_GRACE_SECONDS", 0.2)
        allow(Process).to receive(:kill).and_call_original

        described_class.terminate(SubprocessSpecHelpers::ExitedWaiter.new(pid))

        expect(Process).to have_received(:kill).with("TERM", -pid)
        expect(Process).to have_received(:kill).with("KILL", -pid)
      ensure
        begin
          Process.kill("KILL", -pid)
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end
        reaper.join(2)
        FileUtils.rm_f(ready)
      end
    end
  end

  # @lat: [[subprocess-deadline-design#Why reader joins get a floor, not just the remaining time]]
  describe ".drain_within" do
    it "returns buffered output from an exited child rather than calling a spent budget a timeout" do
      out_r, out_w = IO.pipe
      err_r, err_w = IO.pipe
      begin
        out_w.write("captured")
        out_w.close
        err_w.close
        waiter = SubprocessSpecHelpers::CompletedWaiter.new(
          SubprocessSpecHelpers.reaped_pid, SubprocessSpecHelpers.reaped_status
        )

        out, err, status = described_class.drain_within(
          ["mutool"], out_r, err_r, waiter,
          timeout_seconds: 0, max_stdout_bytes: 1024, max_stderr_bytes: 1024
        )

        expect(out).to eq("captured")
        expect(err).to eq("")
        expect(status).to be_success
      ensure
        [out_r, err_r, out_w, err_w].each { |io| io.close unless io.closed? }
      end
    end

    # @lat: [[subprocess-deadline-design#Why the deadline has to cover draining, not just child exit]]
    it "still raises TimedOut when a reader cannot finish because the pipe stays open" do
      out_r, out_w = IO.pipe
      err_r, err_w = IO.pipe
      begin
        err_w.close
        waiter = SubprocessSpecHelpers::CompletedWaiter.new(
          SubprocessSpecHelpers.reaped_pid, SubprocessSpecHelpers.reaped_status
        )
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect {
          described_class.drain_within(
            ["mutool"], out_r, err_r, waiter,
            timeout_seconds: 0, max_stdout_bytes: 1024, max_stderr_bytes: 1024
          )
        }.to raise_error(described_class::TimedOut, /draining/)

        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
      ensure
        [out_r, err_r, out_w, err_w].each { |io| io.close unless io.closed? }
      end
    end
  end
end
