# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "the per-run frontend build directory" do
  let(:vite_config_source) { Rails.root.join("vite.config.ts").read }

  # Captures only the argument object passed to rails(...), not the whole
  # file — a comment elsewhere in vite.config.ts mentioning buildDir would
  # otherwise satisfy test 2 without the option actually being wired.
  let(:rails_plugin_call) { vite_config_source[/rails\(\{(.*?)\}\)/m, 1] }

  let(:initializers_dir) { Rails.root.join("config", "initializers") }

  let(:initializer_filenames) { Dir.children(initializers_dir).sort }

  # Found by content, not by a hardcoded filename — task 1 must not assume
  # task 2's chosen name for the new initializer.
  let(:vite_build_dir_initializer_name) do
    initializer_filenames.find do |name|
      initializers_dir.join(name).read.match?(/RailsVite\.config\.build_dir\s*=/)
    end
  end

  let(:vite_build_dir_initializer) do
    name = vite_build_dir_initializer_name
    name && initializers_dir.join(name).read
  end

  let(:compose_config) do
    YAML.safe_load(Rails.root.join(".dockerdev", "compose.yml").read, aliases: true)
  end

  let(:rspec_service_command) { compose_config.dig("services", "rspec", "command") }

  let(:rspec_script) { Rails.root.join("scripts", "dip", "rspec.sh").read }

  # Test 1
  it "finds the rails() plugin call in vite.config.ts, so a rename is a red gate rather than a silent pass" do
    expect(rails_plugin_call).to be_present,
      "could not find `rails({ ... })` in vite.config.ts — a rename here would make every other test in this file a silent pass"
  end

  # Test 2
  it "passes buildDir to the rails() plugin from SWAY_VITE_BUILD_DIR, treating an empty value as unset" do
    expect(rails_plugin_call).to include("buildDir"),
      "the rails() call has no buildDir option, so every verify run's frontend build still lands in the one shared public/vite-test directory"
    expect(rails_plugin_call).to include("process.env.SWAY_VITE_BUILD_DIR"),
      "buildDir is not wired to process.env.SWAY_VITE_BUILD_DIR, so verify.sh's per-run directory can never reach the Vite build"
    # The Rails half of this pair guards the same value with .present? — see
    # config/initializers/_vite_build_dir.rb, whose own comment records the
    # measured damage.
    expect(rails_plugin_call).to match(/buildDir:\s*process\.env\.SWAY_VITE_BUILD_DIR\s*\|\|\s*undefined/),
      "buildDir hands an empty SWAY_VITE_BUILD_DIR straight to the plugin, which resolves it with ?? and so " \
      "treats \"\" as a real value — the build directory becomes public/ itself, and Vite empties that directory " \
      "before building, deleting every tracked file under it"
  end

  # Test 3
  it "sets RailsVite.config.build_dir from an initializer, only when SWAY_VITE_BUILD_DIR is present" do
    expect(vite_build_dir_initializer_name).not_to be_nil,
      "no initializer under config/initializers sets RailsVite.config.build_dir — the Rails side of the build-dir split is missing"
    expect(vite_build_dir_initializer).to match(/RailsVite\.config\.build_dir\s*=\s*ENV\[["']SWAY_VITE_BUILD_DIR["']\]\s*if\s+ENV\[["']SWAY_VITE_BUILD_DIR["']\]\.present\?/),
      "the initializer must assign RailsVite.config.build_dir from ENV[\"SWAY_VITE_BUILD_DIR\"] only when it is " \
      "present? (not a bare truthy check), so both an unset variable and an explicitly empty one fall through to " \
      "the gem's own default (vite-test in test, vite elsewhere) — an empty string is truthy in Ruby"
  end

  # Test 4
  it "loads before inertia.rb and content_security_policy.rb, both of which read the manifest through RailsVite" do
    expect(initializer_filenames).not_to be_empty,
      "config/initializers is empty or unreadable, so this check found nothing to order"
    expect(vite_build_dir_initializer_name).not_to be_nil,
      "no build-dir initializer exists yet to check the load order of"

    build_dir_index = initializer_filenames.index(vite_build_dir_initializer_name)
    inertia_index = initializer_filenames.index("inertia.rb")
    csp_index = initializer_filenames.index("content_security_policy.rb")

    expect(inertia_index).not_to be_nil, "config/initializers/inertia.rb not found"
    expect(csp_index).not_to be_nil, "config/initializers/content_security_policy.rb not found"

    expect(build_dir_index).to be < inertia_index,
      "the build-dir initializer sorts after inertia.rb, so inertia.rb sets config.version = RailsVite.digest by reading " \
      "the manifest BEFORE the build directory moves — every Inertia response then carries a version that does not match " \
      "the assets the browser is actually served, and browser specs get full reloads or a 409"
    expect(build_dir_index).to be < csp_index,
      "the build-dir initializer sorts after content_security_policy.rb, which also reads the manifest through RailsVite " \
      "before the build directory moves"
  end

  # Test 5 — must hold in both states: unset (today, and every plain `dip run rspec`)
  # and set (a verify lane). Passes before this plan's change because the unset
  # branch is already the gem's own default.
  it "resolves the live build_dir to SWAY_VITE_BUILD_DIR when set, and to vite-test in test env when unset" do
    if ENV["SWAY_VITE_BUILD_DIR"].present?
      expect(RailsVite.config.build_dir).to eq(ENV["SWAY_VITE_BUILD_DIR"])
    else
      expect(RailsVite.config.build_dir).to eq("vite-test")
    end
  end

  # Test 6 — already true today via the gem's own derivation; pinned so a
  # future change cannot let manifest_path or asset_prefix drift from build_dir.
  it "derives manifest_path and asset_prefix from the same build_dir, so one value moves all three" do
    build_dir = RailsVite.config.build_dir

    expect(RailsVite.config.manifest_path.to_s).to include(build_dir),
      "manifest_path does not contain the resolved build_dir (#{build_dir}), so a per-run directory would not move the manifest with it"
    expect(RailsVite.config.asset_prefix).to include(build_dir),
      "asset_prefix does not contain the resolved build_dir (#{build_dir}), so served asset URLs would not move with a per-run directory"
  end

  # Test 7
  # @lat: [[verification-gates#The frontend test bundle a spec run reads]]
  it "stops the suite when the frontend build fails, rather than running it against the last manifest (L-01)" do
    expect(rspec_service_command).to be_present,
      "no command found for the rspec service in .dockerdev/compose.yml"

    entrypoint = compose_config.dig("services", "rspec", "entrypoint").to_s
    expect(entrypoint).to include("entrypoint.sh"),
      "the rspec service has no entrypoint, so nothing builds the frontend for a run whose command replaces the " \
      "compose command"

    script = Rails.root.join(".dockerdev", "entrypoint.sh").read
    expect(script).to match(/vite-test-build\.sh ensure \|\| exit/),
      "the entrypoint does not stop on a failed build, so a failed build leaves the previous manifest in place, " \
      "rspec renders it, and every page assertion times out at once — reading as catastrophic breakage rather " \
      "than a stale bundle"
  end

  # Test 8 — the plain suite needs its own directory for the same reason a
  # verify lane does, and for one more: Vite empties its output directory
  # before it builds, and with nothing set that directory is the parent of
  # every verify run's own.
  it "gives a plain `dip run rspec` its own build directory, so it cannot empty a verify run's" do
    expect(rspec_script).to match(%r{^SWAY_VITE_BUILD_DIR="vite-test/run-}),
      "scripts/dip/rspec.sh sets no SWAY_VITE_BUILD_DIR of its own, so its `vite build --mode test` writes straight " \
      "into public/vite-test — the parent of every verify run's vite-test/run-<id>, in a volume every checkout " \
      "shares. Vite empties that directory first, so an ordinary suite run deletes a live verify run's whole bundle"
    expect(rspec_script).to match(/-e SWAY_VITE_BUILD_DIR="\$SWAY_VITE_BUILD_DIR"/),
      "scripts/dip/rspec.sh never passes SWAY_VITE_BUILD_DIR to its compose run, so the directory it picks on the " \
      "host never reaches the container that builds the bundle and then reads it"
    expect(rspec_script).not_to match(/^\s*dip compose run/),
      "scripts/dip/rspec.sh starts a container through `dip compose run`, which silently drops -e flags in this " \
      "environment — the flag asserted above would then be written down and delivered nowhere, which " \
      "reads more convincingly than not setting it at all"
  end

  # Test 9
  it "resolves paths inside the built frontend from build_dir, never by naming the directory" do
    ruby_files = Rails.root.glob("{app,lib,spec}/**/*.rb")
    expect(ruby_files.length).to be > 100,
      "found only #{ruby_files.length} Ruby files to scan, so this check would report a clean tree having read almost none of it"

    # Split so that no single line of this file carries the whole shape —
    # otherwise the check matches its own source and can never pass.
    resolver = %q{public_path|root\.join\(\s*["']public["']}
    names_a_build_dir = %q(["'][^"'\n]*vite)
    naming_the_directory = Regexp.new("(?:#{resolver})[^\n]*#{names_a_build_dir}")

    offenders = ruby_files.select { |path| path.read.match?(naming_the_directory) }
      .map { |path| path.relative_path_from(Rails.root).to_s }

    # A hardcoded directory name matches nothing once a run gets its own, and
    # the caller reads an empty set rather than failing: the browser-error
    # spec's precondition went false and it skipped, which reads as a pass.
    expect(offenders).to be_empty,
      "these files reach into the built frontend by naming its directory instead of asking " \
      "RailsVite.config.build_dir where this run built: #{offenders.join(", ")}"
  end

  # @lat: [[verification-gates#The frontend test bundle a spec run reads]]
  it "disables RailsVite.config.auto_build in the test environment" do
    expect(RailsVite.config.auto_build?).to be(false),
      "RailsVite.config.auto_build? is true in test environment, allowing in-process Vite builds " \
      "that can delete and recreate manifest.json during parallel test runs"
  end

  # @lat: [[verification-gates#The frontend test bundle a spec run reads]]
  it "excludes RailsVite::AutoBuild middleware from the middleware stack in test environment" do
    expect(Rails.application.middleware).not_to include(RailsVite::AutoBuild),
      "RailsVite::AutoBuild middleware is present in Rails.application.middleware during tests, " \
      "risking in-process builds on stale manifest checks"
  end
end
