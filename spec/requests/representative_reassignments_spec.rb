# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RepresentativeReassignments", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:sway_locale) { create(:sway_locale) }
  let(:user) do
    create(:user).tap { |u| complete_registration_with_active_link(u) }
  end
  let(:district) { create(:district, sway_locale:) }
  let(:legislator) { create(:legislator, district:) }
  let!(:reassignment) do
    RepresentativeReassignment.create!(
      user: user,
      district: district,
      legislator: legislator,
      reassignment_type: :vacancy_filled
    )
  end

  describe "unauthenticated access" do
    it "redirects unauthenticated users on PATCH dismiss" do
      patch "/reassignment_notifications/#{reassignment.id}/dismiss"
      expect(response).to redirect_to(root_url)
    end
  end

  describe "authenticated dismissal" do
    before do
      sign_in(user)
    end

    it "dismisses a notification via /reassignment_notifications/:id/dismiss" do
      expect {
        patch "/reassignment_notifications/#{reassignment.id}/dismiss", as: :json
      }.to change { reassignment.reload.dismissed_at }.from(nil)

      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 when attempting to dismiss another user's reassignment" do
      other_user = create(:user).tap do |u|
        complete_registration_with_active_link(u)
      end
      other_reassignment = RepresentativeReassignment.create!(
        user: other_user,
        district: district,
        legislator: legislator,
        reassignment_type: :vacancy_filled
      )

      patch "/reassignment_notifications/#{other_reassignment.id}/dismiss", as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "is idempotent across repeated dismissals and safely serializes and renders sparse records with nil associations" do
      patch "/reassignment_notifications/#{reassignment.id}/dismiss", as: :json
      expect(response).to have_http_status(:no_content)
      patch "/reassignment_notifications/#{reassignment.id}/dismiss", as: :json
      expect(response).to have_http_status(:no_content)

      sparse = RepresentativeReassignment.create!(
        user: user,
        district: nil,
        previous_district: nil,
        legislator: nil,
        previous_legislator: nil,
        reassignment_type: :district_changed
      )
      serialized = RepresentativeReassignmentResource.new(sparse).serializable_hash
      expect(serialized).to include("id" => sparse.id, "district" => nil, "legislator" => nil)

      user.update_column(:email, "recipient@example.com")
      mail = RepresentativeReassignmentMailer.reassignment_digest(user, [sparse])
      expect(mail.html_part.body.decoded).to include("Representation Update")
    end
  end

  describe "shared Inertia props" do
    it "shares undismissed reassignments in props" do
      sway_locale, user = setup
      sign_in(user)

      reassignment = RepresentativeReassignment.create!(
        user: user,
        district: user.user_legislators.first.legislator.district || create(:district, sway_locale:),
        legislator: user.user_legislators.first.legislator,
        reassignment_type: :vacancy_filled
      )

      get "/legislators"
      expect(inertia).to render_component Pages::LEGISLATORS
      expect(inertia.props[:reassignment_notifications]).to be_present
      ids = inertia.props[:reassignment_notifications].map { |r| r[:id] || r["id"] }
      expect(ids).to include(reassignment.id)

      reassignment.dismiss!

      get "/legislators"
      expect(inertia).to render_component Pages::LEGISLATORS
      ids = inertia.props[:reassignment_notifications].map { |r| r[:id] || r["id"] }
      expect(ids).not_to include(reassignment.id)
    end
  end
end
