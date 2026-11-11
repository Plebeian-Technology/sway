# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260813000001_clear_our_own_address_from_organization_icons")

# What these pin is the guard, not the count: only an address
# pointing at our own storage is cleared, and a genuine outside source stays.
RSpec.describe "ClearOurOwnAddressFromOrganizationIcons data migration", type: :model do
  let(:migration) { ClearOurOwnAddressFromOrganizationIcons.new }

  def run_icon_url_cleanup
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  it "clears an address that points at our own storage" do
    org = create(:organization, icon_url: "https://sway.vote/rails/active_storage/blobs/proxy/abc/icon.png")

    run_icon_url_cleanup

    expect(org.reload.icon_url).to be_nil
  end

  # The developer machine name in the address is the whole reason this exists,
  # and it is exactly the case a host-based rule would miss.
  it "clears one naming a machine that is not sway.vote" do
    org = create(:organization, icon_url: "http://localhost:3333/rails/active_storage/blobs/proxy/xyz/icon.png")

    run_icon_url_cleanup

    expect(org.reload.icon_url).to be_nil
  end

  it "leaves a genuine outside source alone" do
    org = create(:organization, icon_url: "https://baltimorecity.gov/images/logo.png")

    run_icon_url_cleanup

    expect(org.reload.icon_url).to eq("https://baltimorecity.gov/images/logo.png")
  end

  it "leaves a row that never had one alone" do
    org = create(:organization, icon_url: nil)

    run_icon_url_cleanup

    expect(org.reload.icon_url).to be_nil
  end
end
