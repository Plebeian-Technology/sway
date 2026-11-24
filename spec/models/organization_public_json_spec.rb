# frozen_string_literal: true

require "rails_helper"

# @lat: [[organizations-controller-notes#What PUBLIC_FIELDS is, and the rule around it]]
RSpec.describe "to_public_json whitelists" do
  describe Organization do
    let(:organization) { create(:organization) }

    it "returns only the whitelisted public fields" do
      payload = organization.to_public_json

      expect(payload.keys).to match_array([
        :id, :name, :icon_url, :sway_locale_id, :created_at,
        :sway_locale_slug, :managed_on_sway
      ])
    end

    describe "managed_on_sway" do
      it "is true when the organization has an active member" do
        create(:user_organization_membership, organization: organization, status: "active")

        expect(organization.to_public_json[:managed_on_sway]).to be(true)
      end

      it "is false when the organization's only members are pending or removed" do
        create(:user_organization_membership, organization: organization, status: "pending")
        create(:user_organization_membership, organization: organization, status: "removed")

        expect(organization.to_public_json[:managed_on_sway]).to be(false)
      end

      it "is false when the organization has no members" do
        expect(organization.to_public_json[:managed_on_sway]).to be(false)
      end

      it "uses a batched answer when one is passed" do
        create(:user_organization_membership, organization: organization, status: "active")

        expect(organization.to_public_json(managed_on_sway: false)[:managed_on_sway]).to be(false)
      end
    end

    describe ".managed_on_sway_ids" do
      it "returns the ids among those given that have an active member" do
        managed = create(:organization, name: "Managed Org")
        lapsed = create(:organization, name: "Lapsed Org")
        create(:user_organization_membership, organization: managed, status: "active")
        create(:user_organization_membership, organization: lapsed, status: "removed")

        expect(Organization.managed_on_sway_ids([managed.id, lapsed.id, organization.id]))
          .to contain_exactly(managed.id)
      end
    end

    # @lat: [[organizations-controller-notes#Why icon URL provenance rules exist]]
    it "answers with our own copy of the icon even when the column is empty" do
      organization.update!(icon_url: nil)
      organization.icon.attach(
        io: StringIO.new("icon"),
        filename: "icon.png",
        content_type: "image/png"
      )

      expect(organization.to_public_json[:icon_url]).to be_present
      expect(organization.reload.icon_url).to be_nil
    end

    # @lat: [[testing-the-toolchain#An assertion that cannot fail proves nothing]]
    it "prefers our own copy over the outside address it came from" do
      organization.update!(icon_url: "https://example.org/logo.png")
      organization.icon.attach(
        io: StringIO.new("icon"),
        filename: "icon.png",
        content_type: "image/png"
      )

      resolved = organization.to_public_json[:icon_url]
      expect(resolved).to be_present
      expect(resolved).not_to eq("https://example.org/logo.png")
    end

    it "falls back to the outside address when we hold no copy" do
      organization.update!(icon_url: "https://example.org/logo.png")

      expect(organization.to_public_json[:icon_url]).to eq("https://example.org/logo.png")
    end

    it "never includes admin / internal field names" do
      payload = organization.to_public_json
      forbidden = %i[
        approved_by_id reviewer_id rejection_reason internal_notes admin_notes
        deleted_at owner_email owner_phone created_by_id updated_by_id
      ]
      forbidden.each do |key|
        expect(payload).not_to have_key(key), "to_public_json leaked #{key}"
      end
    end

    it "never accidentally serializes via as_json" do
      # If someone replaces the explicit method with `as_json`, the payload
      # would include attribute names like "name" (string keys). The explicit
      # whitelist always uses Symbol keys.
      payload = organization.to_public_json
      payload.each_key do |key|
        expect(key).to be_a(Symbol), "expected Symbol keys (whitelist), got String key #{key.inspect}"
      end
    end
  end

  describe OrganizationBillPosition do
    let(:organization) { create(:organization) }
    let(:bill) { create(:bill, sway_locale: organization.sway_locale) }
    let(:position) do
      create(
        :organization_bill_position,
        organization: organization,
        bill: bill,
        support: "FOR",
        summary: "Public rationale"
      )
    end

    it "returns only the whitelisted public fields" do
      payload = position.to_public_json
      expect(payload.keys).to match_array(%i[id organization_id bill_id support summary summary_ai_unreviewed active created_at source_kind source_url])
    end

    it "never includes admin / internal field names" do
      payload = position.to_public_json
      forbidden = %i[
        approved_by_id reviewer_id rejection_reason internal_notes admin_notes
        updated_by_id deleted_at
      ]
      forbidden.each do |key|
        expect(payload).not_to have_key(key), "to_public_json leaked #{key}"
      end
    end

    it "uses Symbol keys (whitelist contract — not as_json)" do
      payload = position.to_public_json
      payload.each_key { |k| expect(k).to be_a(Symbol) }
    end
  end
end
