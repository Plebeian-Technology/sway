# frozen_string_literal: true

require "rails_helper"
require "timeout"
require "tmpdir"

module PipelineLocaleLockSpecHelpers
  def with_held_locale(locale_id)
    ready_reader, ready_writer = IO.pipe
    release_reader, release_writer = IO.pipe
    child_pid = fork do
      ready_reader.close
      release_writer.close
      begin
        PipelineLocaleLock.with_locale(locale_id) do
          ready_writer.write("1")
          ready_writer.close
          release_reader.read(1)
        end
        exit! 0
      rescue
        exit! 1
      end
    end
    ready_writer.close
    release_reader.close
    expect(Timeout.timeout(5) { ready_reader.read(1) }).to eq("1")
    yield
  ensure
    [ready_reader, ready_writer, release_reader, release_writer].each do |io|
      io.close unless io.closed?
    end
    if child_pid
      begin
        Timeout.timeout(5) { Process.wait(child_pid) }
      rescue Timeout::Error
        Process.kill("KILL", child_pid)
        Process.wait(child_pid)
        raise
      end
      expect($?&.success?).to eq(true)
    end
  end
end

RSpec.describe "PipelineLocaleLock" do
  # @type self: PipelineLocaleLockSpecContext
  include PipelineLocaleLockSpecHelpers

  it "uses a lock directory beside the primary database" do
    expect(PipelineLocaleLock.directory).to eq(
      Pathname.new("#{ApplicationRecord.connection_db_config.configuration_hash.fetch(:database)}.pipeline_locks").expand_path
    )
  end

  describe "process exclusion" do
    let(:lock_directory) { Pathname.new(Dir.mktmpdir("pipeline-locale-lock")) }

    before { allow(PipelineLocaleLock).to receive(:directory).and_return(lock_directory) }
    after { FileUtils.remove_entry(lock_directory) }

    # @lat: [[bill-session-archiving-tests#Bill session archive tests#Cross-process locale exclusion]]
    it "rejects the same locale across processes while another locale proceeds" do
      with_held_locale(12) do
        expect { PipelineLocaleLock.with_locale(12, wait: false) { :unexpected } }
          .to raise_error(PipelineLocaleLock::Busy)
        expect(PipelineLocaleLock.with_locale(13, wait: false) { :other_locale }).to eq(:other_locale)
      end
      expect(PipelineLocaleLock.with_locale(12, wait: false) { :released }).to eq(:released)
    end

    it "waits for the other process to release the same locale" do
      # @type var waiter: Thread?
      waiter = nil
      with_held_locale(12) do
        started = Queue.new
        waiter = Thread.new do
          started.push(true)
          PipelineLocaleLock.with_locale(12) { :acquired }
        end
        started.pop
        expect(waiter&.join(0.1)).to be_nil
      end
      expect(Timeout.timeout(5) { waiter&.value }).to eq(:acquired)
    ensure
      waiter&.kill
    end

    it "rejects an unresolved run while a known locale is held" do
      with_held_locale(12) do
        expect { PipelineLocaleLock.with_locale(nil, wait: false) { :unexpected } }
          .to raise_error(PipelineLocaleLock::Busy)
      end
      expect(PipelineLocaleLock.with_locale(nil, wait: false) { :global }).to eq(:global)
    end

    it "rejects known and unresolved runs while the global gate is held" do
      with_held_locale(nil) do
        expect { PipelineLocaleLock.with_locale(12, wait: false) { :unexpected } }
          .to raise_error(PipelineLocaleLock::Busy)
        expect { PipelineLocaleLock.with_locale(nil, wait: false) { :unexpected } }
          .to raise_error(PipelineLocaleLock::Busy)
      end
    end

    it "releases both gates after the protected block raises" do
      expect { PipelineLocaleLock.with_locale(12) { raise "operation failed" } }
        .to raise_error(RuntimeError, "operation failed")
      expect(PipelineLocaleLock.with_locale(nil, wait: false) { :released }).to eq(:released)
      with_held_locale(12) do
        expect { PipelineLocaleLock.with_locale(12, wait: false) { :unexpected } }
          .to raise_error(PipelineLocaleLock::Busy)
      end
    end
  end
end
