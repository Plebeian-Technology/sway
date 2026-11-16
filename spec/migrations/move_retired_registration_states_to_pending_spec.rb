# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "migrate", "20261115130000_move_retired_registration_states_to_pending")

RSpec.describe "MoveRetiredRegistrationStatesToPending migration", type: :model do
  self.use_transactional_tests = false

  let(:migration) { Object.const_get(:MoveRetiredRegistrationStatesToPending).new }
  let(:created_user_ids) { [] }

  after do
    User.where(id: created_user_ids).find_each(&:destroy!)
  end

  def create_user_in_status(status, complete:)
    user = create(:user)
    created_user_ids << user.id
    user.update_columns(registration_status: status, is_registration_complete: complete)
    user
  end

  def run_registration_state_migration
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  it "moves processing and failed users to pending" do
    processing_user = create_user_in_status("processing", complete: false)
    failed_user = create_user_in_status("failed", complete: false)

    run_registration_state_migration

    expect(processing_user.reload.registration_status).to eq("pending")
    expect(failed_user.reload.registration_status).to eq("pending")
  end

  it "leaves pending and completed users unchanged" do
    pending_user = create_user_in_status("pending", complete: false)
    completed_user = create_user_in_status("completed", complete: true)

    run_registration_state_migration

    expect(pending_user.reload.registration_status).to eq("pending")
    expect(completed_user.reload.registration_status).to eq("completed")
    expect(completed_user.is_registration_complete).to be(true)
  end

  it "is idempotent when run twice" do
    processing_user = create_user_in_status("processing", complete: false)
    completed_user = create_user_in_status("completed", complete: true)

    run_registration_state_migration
    run_registration_state_migration

    expect(processing_user.reload.registration_status).to eq("pending")
    expect(completed_user.reload.registration_status).to eq("completed")
  end

  it "raises ActiveRecord::IrreversibleMigration on down" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
