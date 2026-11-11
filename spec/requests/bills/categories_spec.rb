# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-categories-request-spec-design#Why re-adding an already-assigned category succeeds instead of erroring]]
RSpec.describe "Bills::Categories", type: :request do
  include_context "SessionDouble"

  # --- Only admins may use these nested /bills/:id/categories paths ---
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/1/categories",
    params: {category_id: 1}

  include_examples "requires sway admin",
    verb: :delete,
    path: "/bills/1/categories/1"

  # --- Admin-authenticated examples ---
  context "as a sway admin" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    let!(:cat_active) { create(:category, name: "Housing", slug: "housing", active: true) }
    let!(:cat_active2) { create(:category, name: "Health", slug: "health", active: true) }
    let!(:cat_active3) { create(:category, name: "Economy", slug: "economy", active: true) }
    let!(:cat_inactive) { create(:category, name: "Deprecated", slug: "deprecated", active: false) }
    let(:bill) { create(:bill) }

    describe "POST /bills/:id/categories — add category to bill" do
      it "associates an active category with the bill" do
        post "/bills/#{bill.id}/categories", params: {category_id: cat_active.id}
        expect(bill.reload.categories).to include(cat_active)
      end

      it "responds with a success status or redirect" do
        post "/bills/#{bill.id}/categories", params: {category_id: cat_active.id}
        expect([200, 201, 302, 303]).to include(response.status)
      end
    end

    describe "DELETE /bills/:id/categories/:category_id — remove category from bill" do
      before do
        Object.const_get("BillCategory").create!(bill: bill, category: cat_active)
      end

      it "dissociates the category from the bill" do
        delete "/bills/#{bill.id}/categories/#{cat_active.id}"
        expect(bill.reload.categories).not_to include(cat_active)
      end

      it "responds with a success status or redirect" do
        delete "/bills/#{bill.id}/categories/#{cat_active.id}"
        expect([200, 204, 302, 303]).to include(response.status)
      end
    end

    describe "POST /bills/:id/categories — cap-3 ceiling rejection (R2: 1..3 cardinality)" do
      before do
        # Pre-assign 3 categories to the bill (already at the cap).
        bill_category_class = Object.const_get("BillCategory")
        bill_category_class.create!(bill: bill, category: cat_active)
        bill_category_class.create!(bill: bill, category: cat_active2)
        bill_category_class.create!(bill: bill, category: cat_active3)
      end

      let!(:cat_active4) { create(:category, name: "Education", slug: "education", active: true) }

      it "rejects adding a 4th category (cap-3 ceiling)" do
        post "/bills/#{bill.id}/categories", params: {category_id: cat_active4.id}
        expect([422, 400, 302, 303]).to include(response.status)
        expect(bill.reload.categories.count).to eq(3)
      end
    end

    describe "POST /bills/:id/categories — V-A-W-01: cap counts ACTIVE only" do
      # The limit counts active categories only, matching what BillCategoryAssigner
      # does. Leftover rows for categories since switched off must not use up any of the
      # three slots, or the admin is blocked from adding one when there is plainly room.
      before do
        bill_category_class = Object.const_get("BillCategory")
        bill_category_class.create!(bill: bill, category: cat_active)    # active
        bill_category_class.create!(bill: bill, category: cat_active2)   # active
        bill_category_class.create!(bill: bill, category: cat_inactive)  # inactive leftover
        # 3 total rows, but only 2 ACTIVE → there is room for one more active category.
      end

      it "allows adding a 3rd ACTIVE category when a leftover inactive row makes 3 total" do
        post "/bills/#{bill.id}/categories", params: {category_id: cat_active3.id}
        expect([200, 201, 302, 303]).to include(response.status)
        expect(bill.reload.categories.where(active: true).count).to eq(3)
        expect(bill.reload.categories.count).to eq(4) # 3 active + 1 inactive leftover
      end

      it "rejects a 4th ACTIVE category once 3 active are assigned (inactive rows ignored)" do
        Object.const_get("BillCategory").create!(bill: bill, category: cat_active3)
        cat_active4 = create(:category, name: "Education", slug: "education", active: true)
        post "/bills/#{bill.id}/categories", params: {category_id: cat_active4.id}
        expect([422, 400, 302, 303]).to include(response.status)
        expect(bill.reload.categories.where(active: true).count).to eq(3)
      end
    end

    describe "POST /bills/:id/categories — R5-B-I-01: idempotent re-add of an already-assigned category" do
      # @lat: [[bill-categories-request-spec-design#Why re-adding an already-assigned category succeeds instead of erroring]]
      let(:json_headers) { {"Accept" => "application/json"} }

      before do
        bill_category_class = Object.const_get("BillCategory")
        bill_category_class.create!(bill: bill, category: cat_active)
        bill_category_class.create!(bill: bill, category: cat_active2)
        bill_category_class.create!(bill: bill, category: cat_active3)
      end

      it "returns 201 (not a cap 422) and does not duplicate the join" do
        expect {
          post "/bills/#{bill.id}/categories",
            params: {category_id: cat_active.id},
            headers: json_headers
        }.not_to change { bill.reload.categories.count }
        expect(response).to have_http_status(:created)
      end
    end

    describe "POST /bills/:id/categories — inactive category rejected on add" do
      it "rejects adding an inactive category" do
        post "/bills/#{bill.id}/categories", params: {category_id: cat_inactive.id}
        expect([422, 400, 302, 303]).to include(response.status)
        expect(bill.reload.categories).not_to include(cat_inactive)
      end
    end

    describe "DELETE /bills/:id/categories/:category_id — inactive-but-already-assigned category is still REMOVABLE" do
      # A category switched off after it was assigned must still be removable. That is
      # what happens when an admin deactivates a category a bill already carries.
      before do
        # Directly create the join (simulates a category that was active when assigned, now inactive).
        Object.const_get("BillCategory").create!(bill: bill, category: cat_inactive)
      end

      it "allows removing an inactive-but-already-assigned category (DELETE succeeds)" do
        delete "/bills/#{bill.id}/categories/#{cat_inactive.id}"
        expect([200, 204, 302, 303]).to include(response.status)
        expect(bill.reload.categories).not_to include(cat_inactive)
      end
    end

    # Check the exact error wording and status codes JSON callers get — the mobile app
    # and in-page requests. The loose status checks above do not pin the words the
    # controller puts in a 422 body.
    describe "JSON surface — create error bodies (Accept: application/json)" do
      let(:json_headers) { {"Accept" => "application/json"} }

      it "returns 422 + 'Maximum 3 categories allowed per bill.' when at the cap-3 ceiling" do
        bill_category_class = Object.const_get("BillCategory")
        bill_category_class.create!(bill: bill, category: cat_active)
        bill_category_class.create!(bill: bill, category: cat_active2)
        bill_category_class.create!(bill: bill, category: cat_active3)
        cat_active4 = create(:category, name: "Education", slug: "education", active: true)

        post "/bills/#{bill.id}/categories",
          params: {category_id: cat_active4.id},
          headers: json_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["error"]).to eq({"code" => "validation_failed", "message" => "Maximum 3 categories allowed per bill."})
        expect(bill.reload.categories.count).to eq(3)
      end

      it "returns 422 + 'Category not found or not available.' for an inactive category" do
        post "/bills/#{bill.id}/categories",
          params: {category_id: cat_inactive.id},
          headers: json_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["error"]).to eq({"code" => "validation_failed", "message" => "Category not found or not available."})
        expect(bill.reload.categories).not_to include(cat_inactive)
      end

      it "returns 422 + 'Category not found or not available.' for an unknown category id" do
        post "/bills/#{bill.id}/categories",
          params: {category_id: 0},
          headers: json_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["error"]).to eq({"code" => "validation_failed", "message" => "Category not found or not available."})
      end
    end

    # The status codes JSON callers get when it works: 201 on add, 200 on remove.
    describe "JSON surface — success status codes (Accept: application/json)" do
      let(:json_headers) { {"Accept" => "application/json"} }

      it "returns 201 Created when an active category is added" do
        post "/bills/#{bill.id}/categories",
          params: {category_id: cat_active.id},
          headers: json_headers

        expect(response).to have_http_status(:created)
        expect(bill.reload.categories).to include(cat_active)
      end

      it "returns 200 OK when a category is removed" do
        Object.const_get("BillCategory").create!(bill: bill, category: cat_active)

        delete "/bills/#{bill.id}/categories/#{cat_active.id}",
          headers: json_headers

        expect(response).to have_http_status(:ok)
        expect(bill.reload.categories).not_to include(cat_active)
      end
    end

    # @lat: [[bill-category-redirect-prop-freshness#Why the active-category counter only counts ACTIVE categories, and stays open when the limit prop is missing]]
    describe "what the redirect lands on" do
      let(:referer) { summary_bill_creator_url(bill) }

      it "renders the bill creator with the added category already in the bill prop" do
        post "/bills/#{bill.id}/categories",
          params: {category_id: cat_active.id},
          headers: {"HTTP_REFERER" => referer}
        follow_redirect!

        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props[:bill][:override_categories].pluck(:name)).to include("Housing")
      end

      it "renders the bill creator with the removed category already gone from the bill prop" do
        Object.const_get("BillCategory").create!(bill: bill, category: cat_active)

        delete "/bills/#{bill.id}/categories/#{cat_active.id}",
          headers: {"HTTP_REFERER" => referer}
        follow_redirect!

        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props[:bill][:override_categories].pluck(:name)).not_to include("Housing")
      end

      # The operator stays where they were. redirect_back_or_to reads the
      # Referer, so the tab they were working in is the tab they land on —
      # which is also why nothing about the pinned run or the open tab is lost.
      it "comes back to the tab the operator was on" do
        post "/bills/#{bill.id}/categories",
          params: {category_id: cat_active.id},
          headers: {"HTTP_REFERER" => referer}

        expect(response).to redirect_to(referer)
      end
    end

    # @lat: [[bill-categories-request-spec-design#Why re-adding an already-assigned category succeeds instead of erroring]]
    describe "web surface — Inertia error shape on create failure" do
      it "redirects back and carries the category error in session[:inertia_errors]" do
        post "/bills/#{bill.id}/categories", params: {category_id: cat_inactive.id}

        expect(response).to have_http_status(:found)
        inertia_errors = session[:inertia_errors] || {}
        expect(inertia_errors[:category] || inertia_errors["category"]).to eq(
          "Category not found or not available."
        )
      end
    end
  end
end
