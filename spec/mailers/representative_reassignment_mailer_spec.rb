# frozen_string_literal: true

require "rails_helper"

RSpec.describe RepresentativeReassignmentMailer, type: :mailer do
  let(:user) { create(:user, email: "citizen@example.com", full_name: "Jane Doe") }
  let(:district) { create(:district, name: "District 46") }
  let(:legislator) { create(:legislator, district:, first_name: "John", last_name: "Smith") }
  let(:prev_legislator) { create(:legislator, district:, first_name: "Bob", last_name: "Jones") }

  describe "#reassignment_digest" do
    it "renders single successor transition email with proper headers and body" do
      reassignment = RepresentativeReassignment.create!(
        user: user,
        district: district,
        legislator: legislator,
        previous_legislator: prev_legislator,
        reassignment_type: :successor_seeded
      )

      mail = described_class.reassignment_digest(user, [reassignment])

      expect(mail.to).to eq(["citizen@example.com"])
      expect(mail.from).to eq(["outreach@sway.vote"])
      expect(mail.subject).to eq("John Smith is your new representative on Sway")

      expect(mail.html_part.body.to_s).to include("John Smith")
      expect(mail.html_part.body.to_s).to include("Bob Jones")
      expect(mail.html_part.body.to_s).to include("District 46")
      expect(mail.html_part.body.to_s).to include("https://sway.vote/legislators")

      expect(mail.text_part.body.to_s).to include("John Smith")
      expect(mail.text_part.body.to_s).to include("Bob Jones")
      expect(mail.text_part.body.to_s).to include("https://sway.vote/legislators")
    end

    it "renders digest subject when multiple reassignments exist" do
      r1 = RepresentativeReassignment.create!(
        user: user,
        district: district,
        legislator: legislator,
        reassignment_type: :vacancy_filled
      )
      dist2 = create(:district, name: "District 43")
      leg2 = create(:legislator, district: dist2, first_name: "Alice", last_name: "Walker")
      r2 = RepresentativeReassignment.create!(
        user: user,
        district: dist2,
        legislator: leg2,
        reassignment_type: :vacancy_filled
      )

      mail = described_class.reassignment_digest(user, [r1, r2])

      expect(mail.subject).to eq("Updates to your elected representatives on Sway")
      expect(mail.html_part.body.to_s).to include("John Smith")
      expect(mail.html_part.body.to_s).to include("Alice Walker")
    end
  end
end
