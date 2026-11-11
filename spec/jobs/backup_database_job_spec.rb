# frozen_string_literal: true

require "rails_helper"

# @lat: [[steep-typed-spec-helpers#Why spec/jobs/backup_database_job_spec.rb writes its instance_double stub inside each example, not in a let]]
RSpec.describe BackupDatabaseJob do
  it "backs up the primary database for the current env" do
    service = instance_double(DatabaseBackupService, call: :ok)
    allow(DatabaseBackupService).to receive(:new).and_return(service)

    described_class.new.perform

    expect(DatabaseBackupService).to have_received(:new).with(db_name: "test")
    expect(service).to have_received(:call).once
  end

  # @lat: [[auxiliary-databases#Why the queue database is left out of the backup deliberately]]
  it "does not back up the queue database" do
    service = instance_double(DatabaseBackupService, call: :ok)
    allow(DatabaseBackupService).to receive(:new).and_return(service)

    described_class.new.perform

    expect(DatabaseBackupService).not_to have_received(:new).with(db_name: "test_queue")
  end

  it "swallows a database failure and logs it rather than raising" do
    allow(DatabaseBackupService).to receive(:new).and_raise(StandardError.new("boom"))
    allow(SwayLogging).to receive(:log_exception)

    expect { described_class.new.perform }.not_to raise_error
    expect(SwayLogging).to have_received(:log_exception).once
  end
end
