# == Schema Information
#
# Table name: user_legislators
# Database name: primary
#
#  id            :integer          not null, primary key
#  active        :boolean          default(TRUE), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  legislator_id :integer          not null
#  user_id       :integer          not null
#
# Indexes
#
#  by_unique_user_and_legislator            (user_id,legislator_id) UNIQUE
#  index_user_legislators_on_legislator_id  (legislator_id)
#
# Foreign Keys
#
#  legislator_id  (legislator_id => legislators.id)
#  user_id        (user_id => users.id)
#
require "rails_helper"

RSpec.describe UserLegislator, type: :model do
  include_context "Setup"

  describe "validations" do
    it "enforces uniqueness of user+legislator at the database level" do
      _sway_locale, user = setup
      # The shared "Setup" context has already created a UserLegislator for this user.
      # Creating that same user-and-legislator pair again has to run into the
      # by_unique_user_and_legislator index.
      existing = UserLegislator.where(user: user).first
      expect(existing).to be_present

      # The rule lives in the database, as the by_unique_user_and_legislator index. A
      # clash there comes back as ActiveRecord::RecordNotUnique. If a uniqueness check
      # is ever added to the model too, the error would be ActiveRecord::RecordInvalid
      # instead. The check below expects whichever one the model produces today.
      expect {
        UserLegislator.create!(user: user, legislator: existing.legislator)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "associations" do
    it "belongs to a user and a legislator" do
      record = create(:user_legislator)
      expect(record.user).to be_a(User)
      expect(record.legislator).to be_a(Legislator)
    end

    it "does NOT auto-create a legacy score row (65-10 retired UserLegislatorScore)" do
      record = create(:user_legislator)
      expect(record.user_legislator_term_scores).to be_empty
    end
  end
end
