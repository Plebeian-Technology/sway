# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "sway:addresses:encrypt_streets" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:addresses:encrypt_streets")
  end

  before { Rake::Task["sway:addresses:encrypt_streets"].reenable }

  def raw_street(address)
    ActiveRecord::Base.connection.select_value("SELECT street FROM addresses WHERE id = #{address.id}")
  end

  # @lat: [[personal-detail-encryption#What is encrypted on an address]]
  it "encrypts a row left in plain words by an earlier release" do
    address = create(:address)
    ActiveRecord::Base.connection.execute("UPDATE addresses SET street = '100 N Holliday St' WHERE id = #{address.id}")
    expect(raw_street(address)).to eq("100 N Holliday St")

    Rake::Task["sway:addresses:encrypt_streets"].invoke

    expect(raw_street(address)).not_to eq("100 N Holliday St")
    expect(Address.find(address.id).street).to eq("100 N Holliday St")
  end

  it "leaves an already encrypted row unchanged" do
    address = create(:address)
    before_ciphertext = raw_street(address)

    Rake::Task["sway:addresses:encrypt_streets"].invoke

    expect(raw_street(address)).to eq(before_ciphertext)
  end
end
