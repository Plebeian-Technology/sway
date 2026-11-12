# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20261112000001_backfill_organization_bill_position_activated_at")

RSpec.describe "BackfillOrganizationBillPositionActivatedAt data migration", type: :model do
  let(:migration) { Object.const_get(:BackfillOrganizationBillPositionActivatedAt).new }

  it "sets activated_at to updated_at for active rows with nil activated_at" do
    updated_time = Time.utc(2026, 10, 15, 14, 30, 0)
    active_row = create(:organization_bill_position, active: true)
    active_row.update_columns(activated_at: nil, updated_at: updated_time)

    ActiveRecord::Migration.suppress_messages { migration.up }

    expect(active_row.reload.activated_at).to eq(updated_time)
  end

  it "leaves inactive rows with nil activated_at" do
    inactive_row = create(:organization_bill_position, active: false)
    inactive_row.update_columns(activated_at: nil)

    ActiveRecord::Migration.suppress_messages { migration.up }

    expect(inactive_row.reload.activated_at).to be_nil
  end

  it "does not overwrite an existing activated_at on active rows and is idempotent" do
    original_activated_at = Time.utc(2026, 9, 1, 9, 0, 0)
    later_updated_at = Time.utc(2026, 10, 1, 9, 0, 0)
    already_set = create(:organization_bill_position, active: true)
    already_set.update_columns(activated_at: original_activated_at, updated_at: later_updated_at)

    ActiveRecord::Migration.suppress_messages { migration.up }
    expect(already_set.reload.activated_at).to eq(original_activated_at)

    expect { ActiveRecord::Migration.suppress_messages { migration.up } }
      .not_to change { already_set.reload.activated_at }
  end
end
