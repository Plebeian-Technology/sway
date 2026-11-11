---
lat:
  mode: how-to
---
# Add an admin-gated endpoint

Adding a controller that only a Sway admin may reach takes three edits, not one. The guard alone passes its own tests while leaking data, so the allowlist and the shared example exist to make the omission loud. Background: [[identity-and-access#The admin gate is a lint rule]].

## Steps

All three edits land in the same change; the lint gate fails the build if the allowlist entry is missing.

1. Add `before_action :verify_is_sway_admin` near the top of the controller class. The filter is defined in `app/controllers/application_controller.rb`.
2. Append the controller's file path to the allowlist in `lib/tasks/sway_lint.rake`.
3. Add `include_examples "requires sway admin", verb:, path:, params:` to the controller's spec. The shared example is defined in `spec/support/shared_examples/requires_sway_admin.rb`.
4. Run `dip run bundle exec rake sway:lint:admin_guards` and confirm it passes.
5. Run the controller's spec and confirm the shared example is exercised.

## Checks

The lint gate is part of the `rake-gates` lane, so a missing step 2 fails `dip run verify` rather than surfacing in production.

- A controller that reaches `ApplicationController` uses this mechanism
- A controller that does not — Active Storage's direct-upload endpoint is the one live case — needs middleware instead, following `AdminOnlyDirectUploads` in `config/initializers/active_storage_admin_uploads.rb`
- "Admin" unqualified means an organization-scoped admin; the application-level role is always `sway_admin`
