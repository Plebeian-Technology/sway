# frozen_string_literal: true

require "rails_helper"
require "rubocop"
require "rubocop/rspec/support"
require Rails.root.join("lib", "cops", "rspec", "inertia_matcher_required")

# Unit spec for this project's own drift-guard cop. It uses RuboCop's
# ExpectOffense harness — the `:config` metadata sets up `cop` along with the
# expect_offense and expect_no_offenses helpers.
RSpec.describe RuboCop::Cop::Sway::InertiaMatcherRequired, :config do
  it "flags a request spec that asserts Inertia props but never pins the component" do
    expect_offense(<<~RUBY)
      RSpec.describe "Bills", type: :request do
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Inertia prop assertions must pin the component with `render_component(...)` so a wrong-component regression fails here. If this example asserts cross-component shared data, exclude the file in .rubocop/rspec.yml.
        it "shows the bill" do
          get "/bills/1"
          expect(inertia).to have_props(bill: {})
        end
      end
    RUBY
  end

  it "accepts a spec that pins the component with render_component" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe "Bills", type: :request do
        it "shows the bill" do
          get "/bills/1"
          expect(inertia).to render_component("Bill")
          expect(inertia).to have_props(bill: {})
        end
      end
    RUBY
  end

  it "ignores JSON specs that never touch the inertia helper" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe "Api", type: :request do
        it "returns json" do
          get "/api/v1/bills"
          expect(JSON.parse(response.body)).to be_an(Array)
        end
      end
    RUBY
  end

  it "does not flag have_flash-only assertions (no component to pin after a redirect)" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe "UserVotes", type: :request do
        it "flashes" do
          post "/user_votes"
          follow_redirect!
          expect(inertia).to have_flash(notice: "Vote saved!")
        end
      end
    RUBY
  end

  it "flags a top-level RSpec.context (a describe alias), not just describe" do
    expect_offense(<<~RUBY)
      RSpec.context "Bills", type: :request do
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Inertia prop assertions must pin the component with `render_component(...)` so a wrong-component regression fails here. If this example asserts cross-component shared data, exclude the file in .rubocop/rspec.yml.
        it "shows the bill" do
          get "/bills/1"
          expect(inertia).to have_props(bill: {})
        end
      end
    RUBY
  end

  it "clears the whole file when render_component appears in any one example" do
    # One sibling describe pins the component, so the block that only asserts
    # props inside the same top-level describe goes unflagged. The cop judges a
    # whole file at once.
    expect_no_offenses(<<~RUBY)
      RSpec.describe "Bills", type: :request do
        describe "GET /index" do
          it "pins" do
            get "/bills"
            expect(inertia).to render_component("Bills")
          end
        end

        describe "GET /show" do
          it "asserts props only" do
            get "/bills/1"
            expect(inertia).to have_props(bill: {})
          end
        end
      end
    RUBY
  end

  it "evaluates each top-level describe independently (a sibling's pin does not cross-clear)" do
    expect_offense(<<~RUBY)
      RSpec.describe "Bills pinned", type: :request do
        it "pins" do
          get "/bills"
          expect(inertia).to render_component("Bills")
        end
      end

      RSpec.describe "Bills unpinned", type: :request do
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Inertia prop assertions must pin the component with `render_component(...)` so a wrong-component regression fails here. If this example asserts cross-component shared data, exclude the file in .rubocop/rspec.yml.
        it "asserts props only" do
          get "/bills/1"
          expect(inertia).to have_props(bill: {})
        end
      end
    RUBY
  end
end
