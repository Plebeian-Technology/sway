# frozen_string_literal: true

namespace :sway do
  namespace :lint do
    # @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule]]
    desc "Ensure all admin-gated controllers carry before_action :verify_is_sway_admin"
    task admin_guards: :environment do
      admin_controllers = [
        "app/controllers/bills_controller.rb",
        "app/controllers/organizations_controller.rb",
        "app/controllers/organization_bill_positions_controller.rb",
        "app/controllers/legislator_votes_controller.rb",
        "app/controllers/buckets/assets_controller.rb",
        "app/controllers/pipeline_runs_controller.rb",
        "app/controllers/bill_draft_org_positions_controller.rb",
        "app/controllers/admin/llm_settings_controller.rb",
        "app/controllers/admin/index_controller.rb",
        "app/controllers/admin/categories_controller.rb",
        "app/controllers/admin/locales_controller.rb",
        "app/controllers/admin/shared_addresses_controller.rb",
        "app/controllers/admin/system_prompts_controller.rb",
        "app/controllers/bills/categories_controller.rb",
        # @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#The organization gate is linted the same way, for the same reason]]
        "app/controllers/bill_of_the_month_schedule_controller.rb",
        "app/controllers/testimony_coverage_acknowledgements_controller.rb",
        "app/controllers/campaigns_controller.rb",
        "app/controllers/sending_service_domains_controller.rb",
        "app/controllers/admin/bill_summary_reports_controller.rb",
        "app/controllers/admin/registration_funnel_controller.rb",
        "app/controllers/admin/partner_reports_controller.rb",
        "app/controllers/admin/bill_news_articles_controller.rb",
        "app/controllers/admin/user_address_changes_controller.rb"
      ]
      offenders = admin_controllers.reject do |path|
        Rails.root.join(path).read.match?(/^\s*before_action\s+:verify_is_sway_admin/)
      end
      if offenders.any?
        warn "Missing before_action :verify_is_sway_admin in:"
        offenders.each { |o| warn "  - #{o}" }
        abort "Admin gate missing. Re-add before_action :verify_is_sway_admin, or update the allowlist in lib/tasks/sway_lint.rake."
      end

      documented = Rails.root.join("CLAUDE.md").read
        .scan(%r{^- `(app/controllers/\S+_controller\.rb)`$}).flatten
      undocumented = admin_controllers - documented
      overdocumented = documented - admin_controllers
      if undocumented.any? || overdocumented.any?
        warn "CLAUDE.md's admin-gated controller list disagrees with this allowlist:"
        undocumented.each { |o| warn "  - missing from CLAUDE.md: #{o}" }
        overdocumented.each { |o| warn "  - in CLAUDE.md but not gated here: #{o}" }
        abort "Reconcile the list in CLAUDE.md (\"Admin-gated controllers\") with lib/tasks/sway_lint.rake."
      end

      enforcement_line = Rails.root.join("CLAUDE.md").read.lines.find do |line|
        line.include?("bundle exec rake sway:lint:admin_guards")
      end
      if enforcement_line&.match?(/\b\d+\b/)
        abort "Do not spell out a controller count in CLAUDE.md (\"Admin Endpoints\"). Refer to the list dynamically."
      end

      puts "All #{admin_controllers.length} admin-gated controllers carry before_action :verify_is_sway_admin, and CLAUDE.md lists the same #{documented.length}."
    end

    # @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#The organization gate is linted the same way, for the same reason]]
    desc "Ensure org-admin controllers carry before_action :verify_is_organization_admin!"
    task org_admin_guards: :environment do
      org_admin_controllers = [
        "app/controllers/organizations/membership_invites_controller.rb",
        "app/controllers/organizations/memberships_controller.rb",
        "app/controllers/organizations/positions_controller.rb",
        "app/controllers/organizations/position_changes_controller.rb"
      ]
      offenders = org_admin_controllers.reject do |path|
        Rails.root.join(path).read.match?(/^\s*before_action\s+:verify_is_organization_admin!/)
      end
      if offenders.any?
        warn "Missing before_action :verify_is_organization_admin! in:"
        offenders.each { |o| warn "  - #{o}" }
        abort "Org-admin gate missing. Re-add before_action :verify_is_organization_admin!, or update the allowlist in lib/tasks/sway_lint.rake."
      end
      puts "All #{org_admin_controllers.length} org-admin controllers carry before_action :verify_is_organization_admin!"
    end

    # @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#The organization gate is linted the same way, for the same reason]]
    desc "Ensure every Inertia request spec pins its component (Sway/InertiaMatcherRequired)"
    task :inertia_matchers do
      require "rubocop"
      status = RuboCop::CLI.new.run(
        ["--only", "Sway/InertiaMatcherRequired", "--format", "simple", "spec/requests"]
      )
      unless status.zero?
        abort(
          "Inertia request specs must pin their component with " \
          "render_component(...). See lib/cops/rspec/inertia_matcher_required.rb."
        )
      end
      puts "All Inertia request specs pin their component (Sway/InertiaMatcherRequired)."
    end

    # @lat: [[env-read-check-design#Why it stays plain Ruby]]
    desc "Forbid an ENV read anywhere in app/ outside the credential door"
    task :env_reads do
      require_relative "../env_read_check"

      root = File.expand_path("../..", __dir__)
      check = EnvReadCheck.new(root)
      begin
        offences = check.offences
      rescue EnvReadCheck::MissingAllowlistedPathError => e
        abort "sway:lint:env_reads: #{e.message}"
      end

      if check.skipped_paths.any?
        warn "Skipped (unrecognized extension): #{check.skipped_paths.join(", ")}"
      end

      disallowed = offences.reject { |o| check.allowed_paths.include?(o.path) }
      if disallowed.any?
        warn "ENV read(s) found outside #{check.allowed_paths.join(", ")} in:"
        disallowed.each { |o| warn "  - #{o}" }
        abort(
          "Read a setting through Sway::Settings, or a credential " \
          "through EnvSecret (app/lib/env_secret.rb). See lib/env_read_check.rb."
        )
      end

      allowed_found = offences.length - disallowed.length
      puts "Scanned #{check.scanned_paths.length} file(s) under app/; " \
        "#{allowed_found} allowed read(s) at #{check.allowed_paths.join(", ")}."
    end

    # @lat: [[migrations-name-no-model#The gate]]
    desc "Forbid a migration naming a model class it does not define itself"
    task :migration_models do
      require_relative "../migration_model_check"

      root = File.expand_path("../..", __dir__)
      check = MigrationModelCheck.new(root)
      begin
        offences = check.offences
      rescue MigrationModelCheck::MissingAllowlistedPathError => e
        abort "sway:lint:migration_models: #{e.message}"
      end

      if offences.any?
        warn "Migration(s) naming a class app/models defines:"
        offences.each { |offence| warn "  - #{offence}" }
        abort(
          "Give the migration its own stand-in class that knows only " \
          "the table name, the way db/migrate/20260420000001_normalize_user_phones.rb " \
          "does. See lib/migration_model_check.rb."
        )
      end

      puts "Scanned #{check.scanned_paths.length} migration(s); none names a model class."
    end

    # @lat: [[identity-scoped-prop-caches#The gate]]
    desc "Forbid an Inertia prop cache whose key does not say whose props they are"
    task :inertia_prop_cache do
      require_relative "../inertia_prop_cache_check"

      root = File.expand_path("../..", __dir__)
      check = InertiaPropCacheCheck.new(root)
      begin
        offences = check.offences
      rescue InertiaPropCacheCheck::MissingAllowlistedPathError => e
        abort "sway:lint:inertia_prop_cache: #{e.message}"
      end

      if offences.any?
        warn "Inertia prop cache(s) with no user, locale or role in the key:"
        offences.each { |offence| warn "  - #{offence}" }
        abort(
          "Put the reader in the key, or cache only the shared part " \
          "and merge the per-user part in after the cache read, the way " \
          "app/controllers/api/v1/bootstrap_controller.rb does. " \
          "See lib/inertia_prop_cache_check.rb."
        )
      end

      puts "Scanned #{check.scanned_paths.length} file(s) under app/; no unscoped prop cache."
    end

    # @lat: [[query-parameter-namespaces#Machine-readable registry and lint enforcement]]
    desc "Ensure query parameters are uniquely owned by features with no cross-feature collisions"
    task :param_names do
      require_relative "../query_parameter_check"

      root = File.expand_path("../..", __dir__)
      check = QueryParameterCheck.new(root)
      begin
        offences = check.offences
      rescue QueryParameterCheck::EmptyRegistryError,
        QueryParameterCheck::InvalidRegistryError,
        QueryParameterCheck::MissingRegistryFileError => e
        abort "sway:lint:param_names: #{e.message}"
      end

      if offences.any?
        warn "Query parameter collision(s) detected:"
        offences.each { |offence| warn "  - #{offence}" }
        abort(
          "Canonical query parameters must be uniquely owned by a single feature. " \
          "See config/query_parameters.yml."
        )
      end

      puts "Scanned #{check.scanned_count} parameter name(s) across #{check.features.length} feature(s); all canonical parameters are unique."
    end
  end
end
