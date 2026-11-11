# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "sway:users:encrypt_personal_details" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:users:encrypt_personal_details")
  end

  before { Rake::Task["sway:users:encrypt_personal_details"].reenable }

  def raw_full_name(user)
    ActiveRecord::Base.connection.select_value("SELECT full_name FROM users WHERE id = #{user.id}")
  end

  # @lat: [[personal-detail-encryption#Converting the rows that already exist]]
  it "encrypts a row left in plain words by an earlier release" do
    user = create(:user, full_name: "Ada Lovelace")
    ActiveRecord::Base.connection.execute("UPDATE users SET full_name = 'Ada Lovelace' WHERE id = #{user.id}")
    expect(raw_full_name(user)).to eq("Ada Lovelace")

    Rake::Task["sway:users:encrypt_personal_details"].invoke

    expect(raw_full_name(user)).not_to eq("Ada Lovelace")
    expect(User.find(user.id).full_name).to eq("Ada Lovelace")
  end

  it "leaves an already encrypted row's value unchanged" do
    user = create(:user, full_name: "Ada Lovelace")
    before_ciphertext = raw_full_name(user)

    Rake::Task["sway:users:encrypt_personal_details"].invoke

    expect(raw_full_name(user)).to eq(before_ciphertext)
    expect(User.find(user.id).full_name).to eq("Ada Lovelace")
  end

  it "keeps going past a row it cannot convert" do
    good = create(:user, full_name: "Ada Lovelace")
    bad = create(:user, full_name: "Grace Hopper")
    ActiveRecord::Base.connection.execute("UPDATE users SET full_name = 'Ada Lovelace' WHERE id = #{good.id}")
    good.reload
    allow(User).to receive(:find_each).and_yield(failing_user(bad)).and_yield(good)

    expect { Rake::Task["sway:users:encrypt_personal_details"].invoke }.not_to raise_error
    expect(raw_full_name(good)).not_to eq("Ada Lovelace")
  end

  def failing_user(user)
    allow(user).to receive(:encrypted_attribute?).and_return(false)
    allow(user).to receive(:encrypt).and_raise(ActiveRecord::StatementInvalid, "database is locked")
    user
  end
end
