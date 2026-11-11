# frozen_string_literal: true

require "rails_helper"

# The public /version and /licenses pages, which say what build is running and
# what it is made of. Both are open to everyone on purpose — being open about
# the software is part of the civic mission — the same as the marketing pages.
RSpec.describe "Meta", type: :request do
  describe "GET /version" do
    it "returns 200 for an unauthenticated visitor (public, no redirect)" do
      get "/version"

      expect(response).to have_http_status(:ok)
      expect(response).not_to be_redirect
    end

    it "renders the Version page with the shared release prop" do
      get "/version"

      expect(inertia).to render_component(Pages::VERSION)
      # @lat: [[testing-the-toolchain#An assertion that cannot fail proves nothing]]
      expect(inertia.props[:release]).to include(:version, :short_sha, :built_from_committed_tree)
    end

    # @lat: [[testing-the-toolchain#An assertion that cannot fail proves nothing]]
    it "carries what the deploy recorded about the build, not just the key" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SWAY_UNCOMMITTED_DIGEST").and_return("a1b2c3d4")

      get "/version"

      release = inertia.props[:release]
      expect(release[:uncommitted_digest]).to eq("a1b2c3d4")
      expect(release[:built_from_committed_tree]).to be(false)
    end
  end

  describe "GET /licenses" do
    it "returns 200 for an unauthenticated visitor (public)" do
      get "/licenses"

      expect(response).to have_http_status(:ok)
    end

    it "renders the Licenses page with a non-MIT frontend dependency list" do
      get "/licenses"

      expect(inertia).to render_component(Pages::LICENSES)
      expect(inertia.props[:licenses]).to be_an(Array)
      expect(inertia.props[:licenses].pluck(:license)).not_to include("MIT")
    end
  end
end
