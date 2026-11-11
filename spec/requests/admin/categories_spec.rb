# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Categories", type: :request do
  include_context "SessionDouble"

  # --- Only admins may reach these routes; everyone else is turned away ---
  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/categories"

  include_examples "requires sway admin",
    verb: :post,
    path: "/admin/categories",
    params: {category: {name: "Test"}}

  include_examples "requires sway admin",
    verb: :patch,
    path: "/admin/categories/1",
    params: {category: {active: false}}

  include_examples "requires sway admin",
    verb: :delete,
    path: "/admin/categories/1"

  # --- Admin-authenticated examples ---
  context "as a sway admin" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    describe "POST /admin/categories — create" do
      it "adds a new category to the database" do
        expect {
          post "/admin/categories", params: {category: {name: "New Category"}}
        }.to change { Object.const_get("Category").count }.by(1)
      end

      it "redirects after create" do
        post "/admin/categories", params: {category: {name: "New Category"}}
        expect(response).to redirect_to("/admin/categories")
      end
    end

    describe "PATCH /admin/categories/:id — rename" do
      let!(:category) { create(:category, name: "Old Name", slug: "old-name", active: true) }

      it "updates the category name" do
        patch "/admin/categories/#{category.id}", params: {category: {name: "New Name"}}
        expect(category.reload.name).to eq("New Name")
      end

      it "does NOT change the stored slug on rename (slug is stable)" do
        patch "/admin/categories/#{category.id}", params: {category: {name: "New Name"}}
        expect(category.reload.slug).to eq("old-name")
      end

      # Renaming has to trim spaces off both ends of the name before saving, the same
      # way creating a category already does.
      it "strips surrounding whitespace from the new name before persisting (NEW-IN-B)" do
        patch "/admin/categories/#{category.id}",
          params: {category: {name: "  New Name  "}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:ok)
        expect(category.reload.name).to eq("New Name")
      end
    end

    # @lat: [[admin-categories-controller-design#update: why the rename collision check also covers current names]]
    describe "PATCH /admin/categories/:id — WR-05 slug-collision rejection on rename" do
      let!(:cat_health) { create(:category, name: "Health", slug: "health", active: true) }
      # A second category with a different stored slug, standing in for one whose
      # current name would slugify to the same value as "Health" after a rename.
      let!(:cat_other) { create(:category, name: "Healthcare", slug: "healthcare", active: true) }

      it "rejects a rename whose slugified name collides with another category's slugified name" do
        # Renaming cat_other to "Health" gives slugify("Health") = "health",
        # which collides with slugify(cat_health.name) = "health".
        patch "/admin/categories/#{cat_other.id}",
          params: {category: {name: "Health"}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "details", "category", "name")).to eq("Category name is already taken.")
        expect(cat_other.reload.name).to eq("Healthcare")
      end

      it "allows a rename that does NOT slug-collide with any other category" do
        patch "/admin/categories/#{cat_other.id}",
          params: {category: {name: "Mental Health"}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:ok)
        expect(cat_other.reload.name).to eq("Mental Health")
      end
    end

    # The same-slug check has to cover creating a category, not only renaming one.
    # #create used to compare against the stored slug alone, and a rename never changes
    # that. So once a category had been renamed, a brand-new category whose name
    # slugified to the renamed one slipped straight through.
    describe "POST /admin/categories — W-01 create-path slug-collision (post-rename)" do
      it "rejects a create whose slugified name collides with a renamed category's current name" do
        # 1. Create "Wellness" (stored slug "wellness").
        post "/admin/categories", params: {category: {name: "Wellness"}}
        wellness = Object.const_get("Category").find_by(slug: "wellness")
        # 2. Rename it to "Health Care" — stored slug stays "wellness",
        #    but slugify("Health Care") == "health-care".
        patch "/admin/categories/#{wellness.id}", params: {category: {name: "Health Care"}}
        expect(wellness.reload.name).to eq("Health Care")

        # 3. Creating "Health-Care" slugifies to "health-care" — collides with the
        #    renamed category even though NO stored slug equals "health-care".
        expect {
          post "/admin/categories",
            params: {category: {name: "Health-Care"}},
            headers: {"Accept" => "application/json"}
        }.not_to change { Object.const_get("Category").count }
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "details", "category", "name")).to eq("Category name is already taken.")
      end

      # When a new name's slug matches the stored slug of a category that has since been
      # renamed, the error has to be the clear "already taken" wording, not the vague
      # "Category name is invalid." that simply rescuing the database uniqueness error
      # would produce.
      it "returns 'already taken' (not 'invalid') when a create collides with a renamed category's frozen stored slug" do
        post "/admin/categories", params: {category: {name: "Wellness"}}
        wellness = Object.const_get("Category").find_by(slug: "wellness")
        patch "/admin/categories/#{wellness.id}", params: {category: {name: "Health Care"}}
        # Stored slug stays "wellness"; current name slugifies to "health-care".
        expect(wellness.reload.slug).to eq("wellness")

        # Re-creating "Wellness" → slugify("Wellness") == "wellness" matches the
        # renamed row's frozen stored slug (but NOT its current-name slug).
        expect {
          post "/admin/categories",
            params: {category: {name: "Wellness"}},
            headers: {"Accept" => "application/json"}
        }.not_to change { Object.const_get("Category").count }
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "details", "category", "name")).to eq("Category name is already taken.")
        expect(response.body).not_to include("invalid")
      end

      # @lat: [[admin-categories-controller-design#update: why the rename collision check also covers current names]]
      it "returns 'already taken' (not the reactivate hint) when colliding a renamed-then-deactivated stored slug" do
        post "/admin/categories", params: {category: {name: "Wellness"}}
        wellness = Object.const_get("Category").find_by(slug: "wellness")
        patch "/admin/categories/#{wellness.id}", params: {category: {name: "Health Care"}}
        patch "/admin/categories/#{wellness.id}", params: {category: {active: false}}
        expect(wellness.reload.slug).to eq("wellness")
        expect(wellness.reload.active).to be(false)

        # slugify("Wellness") == "wellness" matches the frozen stored slug of the
        # renamed-then-deactivated row, but its current name ("Health Care") does not.
        post "/admin/categories",
          params: {category: {name: "Wellness"}},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "details", "category", "name")).to eq("Category name is already taken.")
        expect(response.body).not_to include("Reactivate it instead")
      end
    end

    # Reactivating sends active: true and no name, so the controller's check — which
    # only runs when a name is supplied — never fires. The Category model's own
    # validation is the last line of defence: it has to refuse to switch a deactivated
    # category back on when its slug would clash with an active category's.
    describe "PATCH /admin/categories/:id — W-01 reactivate re-checks slug collision" do
      it "rejects reactivating a category that now slug-collides with an active one" do
        create(:category, name: "Alpha", slug: "alpha", active: true)
        # Stand in for old data: a deactivated row whose slug clashes with the active
        # "Alpha", saved back when no uniqueness check existed.
        dormant = Object.const_get("Category").new(name: "alpha", slug: "alpha-2", active: false)
        dormant.save!(validate: false)

        patch "/admin/categories/#{dormant.id}",
          params: {category: {active: true}},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:unprocessable_content)
        expect(dormant.reload.active).to be(false)
      end
    end

    # @lat: [[admin-categories-controller-design#update: why reactivation is blocked against the per-bill cap]]
    describe "PATCH /admin/categories/:id — R5-B-W-01 reactivation ≤3-active per-bill cap guard" do
      let(:bill) { create(:bill) }
      let!(:cat_a) { create(:category, name: "Alpha", slug: "alpha", active: true) }
      let!(:cat_b) { create(:category, name: "Beta", slug: "beta", active: true) }
      let!(:cat_c) { create(:category, name: "Gamma", slug: "gamma", active: true) }
      let!(:dormant) { create(:category, name: "Delta", slug: "delta", active: false) }

      before do
        [cat_a, cat_b, cat_c, dormant].each do |c|
          Object.const_get("BillCategory").create!(bill: bill, category: c)
        end
      end

      it "rejects a reactivation that would push a bill to 4 active categories" do
        # bill: A,B,C active (3) + Delta inactive → reactivating Delta = 4 active.
        patch "/admin/categories/#{dormant.id}",
          params: {category: {active: true}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "details", "category", "name")).to match(/exceed the 3-category limit/)
        expect(dormant.reload.active).to be(false)
      end

      it "allows a reactivation that lands the bill at exactly 3 active categories" do
        # Drop one active directly so the bill sits at 2 active + 2 inactive; reactivating
        # Delta then yields 3 active — within the cap.
        cat_c.update!(active: false)
        patch "/admin/categories/#{dormant.id}",
          params: {category: {active: true}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:ok)
        expect(dormant.reload.active).to be(true)
      end

      it "allows reactivation of a category assigned to no over-cap bill" do
        lonely = create(:category, name: "Epsilon", slug: "epsilon", active: false)
        patch "/admin/categories/#{lonely.id}",
          params: {category: {active: true}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:ok)
        expect(lonely.reload.active).to be(true)
      end
    end

    describe "PATCH /admin/categories/:id — soft-deactivate" do
      let!(:category) { create(:category, name: "Housing", slug: "housing", active: true) }
      let(:bill) { create(:bill) }
      let!(:bill_category_join) do
        Object.const_get("BillCategory").create!(bill: bill, category: category)
      end

      it "sets active: false on the category" do
        patch "/admin/categories/#{category.id}", params: {category: {active: false}}
        expect(category.reload.active).to be(false)
      end

      it "preserves existing bill↔category join rows on soft-deactivate (R7 — join survives)" do
        patch "/admin/categories/#{category.id}", params: {category: {active: false}}
        # The bill still has the category in its join, even though the category is now inactive.
        expect(bill.reload.categories).to include(category)
      end

      it "redirects after soft-deactivate" do
        patch "/admin/categories/#{category.id}", params: {category: {active: false}}
        expect(response).to redirect_to("/admin/categories")
      end
    end

    # Permanent delete, allowed only once the category is switched off: deactivate
    # first, then delete.
    describe "DELETE /admin/categories/:id — destroy" do
      context "when the category is deactivated" do
        let!(:category) { create(:category, name: "Retired", slug: "retired", active: false) }

        it "permanently deletes the category" do
          expect {
            delete "/admin/categories/#{category.id}"
          }.to change { Object.const_get("Category").count }.by(-1)
          expect(Object.const_get("Category").find_by(id: category.id)).to be_nil
        end

        it "cascades to the bill_categories JOIN rows (dependent: :destroy)" do
          bill = create(:bill)
          Object.const_get("BillCategory").create!(bill: bill, category: category)
          expect {
            delete "/admin/categories/#{category.id}"
          }.to change { Object.const_get("BillCategory").where(category_id: category.id).count }.to(0)
        end

        it "redirects after delete" do
          delete "/admin/categories/#{category.id}"
          expect(response).to redirect_to("/admin/categories")
        end
      end

      context "when the category is still active" do
        let!(:category) { create(:category, name: "Live", slug: "live", active: true) }

        it "rejects the delete and keeps the category" do
          expect {
            delete "/admin/categories/#{category.id}",
              headers: {"Accept" => "application/json"}
          }.not_to change { Object.const_get("Category").count }
          expect(response).to have_http_status(:unprocessable_content)
          body = JSON.parse(response.body)
          expect(body.dig("error", "details", "category", "name")).to eq("Deactivate the category before deleting it.")
        end
      end
    end

    describe "GET /admin/categories — index" do
      let!(:cat1) { create(:category, name: "Housing", slug: "housing", active: true) }
      let!(:cat2) { create(:category, name: "Health", slug: "health", active: true) }
      let(:bill) { create(:bill) }

      before do
        Object.const_get("BillCategory").create!(bill: bill, category: cat1)
      end

      it "renders an Inertia response" do
        get "/admin/categories"
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component("admin/Categories")
      end

      it "exposes a categories list in the Inertia props" do
        get "/admin/categories"
        expect(inertia.props[:categories]).to be_an(Array)
        expect(inertia.props[:categories]).not_to be_empty
      end

      it "includes bill counts per category in the Inertia props" do
        get "/admin/categories"
        cat_with_count = inertia.props[:categories].find { |c|
          c[:name] == "Housing" || c["name"] == "Housing"
        }
        expect(cat_with_count).to be_present
        bill_count = cat_with_count[:bill_count] || cat_with_count["bill_count"]
        expect(bill_count).to eq(1)
      end
    end

    # --- The exact wording of the error messages ---
    # @lat: [[admin-categories-controller-design#Why the validation-copy examples request JSON]]
    describe "POST /admin/categories — validation error copy (60-UI-SPEC contract)" do
      it "returns 422 with 'Category name is required.' for a blank name" do
        post "/admin/categories",
          params: {category: {name: ""}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "details", "category", "name")).to eq("Category name is required.")
        expect(response.body).not_to include("Validation failed")
      end

      it "returns 422 with 'Category name is already taken.' for an active name collision" do
        create(:category, name: "Housing", slug: "housing", active: true)
        post "/admin/categories",
          params: {category: {name: "Housing"}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "details", "category", "name")).to eq("Category name is already taken.")
        expect(response.body).not_to include("Validation failed")
      end

      it "returns the reactivate hint for a name colliding a soft-deactivated category" do
        create(:category, name: "Housing", slug: "housing", active: false)
        post "/admin/categories",
          params: {category: {name: "Housing"}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "details", "category", "name")).to eq(
          "A category with that name is deactivated. Reactivate it instead."
        )
        expect(response.body).not_to include("Validation failed")
      end

      # A name made only of punctuation slugifies to an empty string. That used to fall
      # through to the vague "Category name is invalid.", which hid the real cause. The
      # empty-slug case has to say something specific.
      it "returns a descriptive message for a punctuation-only name (IN-03)" do
        post "/admin/categories",
          params: {category: {name: "!!!"}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "details", "category", "name")).to match(/letter or number/)
        expect(response.body).not_to include("invalid")
      end

      it "returns a descriptive message for a punctuation-only name on rename (IN-03)" do
        category = create(:category, name: "Environment", slug: "environment", active: true)
        patch "/admin/categories/#{category.id}",
          params: {category: {name: "---"}},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "details", "category", "name")).to match(/letter or number/)
        expect(category.reload.name).to eq("Environment")
      end
    end

    # @lat: [[backfill-bill-categories-scope#Why the unmatched-stamp log is at warn, not silent]]
    describe "taxonomy writes re-arm unmatched categorization" do
      let(:bill) { create(:bill) }
      let!(:provisioning) do
        create(:bill_llm_provisioning, bill: bill, categories_unmatched_at: 1.day.ago)
      end

      it "clears the stamp when a category is added" do
        post "/admin/categories",
          params: {category: {name: "Transit"}},
          headers: {"Accept" => "application/json"}

        expect(provisioning.reload.categories_unmatched_at).to be_nil
      end

      it "clears the stamp when a category is renamed" do
        category = create(:category, name: "Environment", slug: "environment", active: true)

        patch "/admin/categories/#{category.id}",
          params: {category: {name: "Environment and Energy"}},
          headers: {"Accept" => "application/json"}

        expect(provisioning.reload.categories_unmatched_at).to be_nil
      end

      it "clears the stamp when a category is reactivated" do
        category = create(:category, name: "Transit", slug: "transit", active: false)

        patch "/admin/categories/#{category.id}",
          params: {category: {active: true}},
          headers: {"Accept" => "application/json"}

        expect(provisioning.reload.categories_unmatched_at).to be_nil
      end

      # @lat: [[admin-categories-controller-design#destroy: two-step delete and why it skips the re-arm]]
      it "leaves the stamp alone when a deactivated category is deleted" do
        category = create(:category, name: "Retired", slug: "retired", active: false)

        delete "/admin/categories/#{category.id}",
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:no_content)
        expect(provisioning.reload.categories_unmatched_at).to be_present
      end
    end
  end
end
