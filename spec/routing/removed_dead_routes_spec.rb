# frozen_string_literal: true

require "rails_helper"

# @lat: [[removed-dead-routes-history#The old email and user-detail endpoints]]
RSpec.describe "Removed dead routes", type: :routing do
  # @lat: [[removed-dead-routes-history#The old email and user-detail endpoints]]
  it "does not route the legacy top-level POST /email_verification (modern: /users/email_verification)" do
    expect(post: "/email_verification").not_to be_routable
    expect(post: "/users/email_verification").to be_routable
  end

  it "routes POST /user_legislator_emails again (modern create path)" do
    expect(post: "/user_legislator_emails").to be_routable
  end

  it "does not route POST /users/details (full_name capture folded into the send form)" do
    expect(post: "/users/details").not_to be_routable
  end

  # @lat: [[removed-dead-routes-history#The JSON GET endpoints nobody owned]]
  it "does not route the deleted user-districts / user-legislator-scores endpoints" do
    expect(get: "/user_districts").not_to be_routable
    expect(get: "/user_legislator_scores").not_to be_routable
    expect(get: "/user_legislator_scores/1").not_to be_routable
  end

  # The bulk endpoint is the only orphan-delete surface.
  it "does not route the single-row DELETE /pipeline_runs/:id/orphan" do
    expect(delete: "/pipeline_runs/1/orphan").not_to be_routable
    expect(delete: "/pipeline_runs/orphans").to be_routable
  end

  it "keeps POST /legislator_votes but drops its orphan top-level GET reads" do
    expect(post: "/legislator_votes").to be_routable
    expect(get: "/legislator_votes").not_to be_routable
    expect(get: "/legislator_votes/1").not_to be_routable

    # The twin under /api still serves reads to bearer-token clients.
    expect(get: "/api/legislator_votes").to be_routable
  end
end
