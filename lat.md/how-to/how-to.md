# How-to

Recipes for tasks that recur, written as ordered steps. Each one assumes the reader already knows why the task matters and links back to [[explanation]] for that.

<!-- lat:index:begin -->
- [Add a SwayLocale](add-a-sway-locale.md) — This procedure describes onboarding a SwayLocale from a declarative YAML document. It produces a seeded SwayLocale with verified representative matching; unsupported automation remains visibly unavailable.
- [Add an admin-gated endpoint](add-an-admin-endpoint.md) — Adding a controller that only a Sway admin may reach takes three edits, not one. The guard alone passes its own tests while leaking data, so the allowlist and the shared example exist to make the omission loud. Background: \[\[identity-and-access#The admin gate is a lint rule\]\].
- [Archive bills after a session rollover](archive-previous-session-bills.md) — Archive a locale's older unfeatured bills after its new session starts. \[\[bill-session-archiving\]\] defines eligibility and the preserved history.
- [Litestream — replication and restore runbook](litestream-restore.md) — **The addresses and account names are not in this file.** They describe one installation, and this repository is public.
- [Move Sway to a new host](move-to-a-new-host.md) — Move a running Sway installation, its SQLite database included, from the host that serves it now \(the old host\) to a different machine \(the new host\). The site is down for the length of the window.
- [Newsroom partner integration](newsroom-partner-integration.md) — How partner newsrooms embed interactive Sway bill cards into legislative coverage, configure attribution parameters, and track civic engagement while safeguarding voter privacy.
- [Publish the GitHub Wiki from lat.md](publish-the-github-wiki.md) — The Diátaxis documentation in \`lat.md/\` compiles into GitHub's \`<repo>.wiki.git\` repository through \[\[scripts/github_wiki_builder.rb#GitHubWikiBuilder\]\] and \`scripts/build-github-wiki.rb\`. Why the builder rewrites links and flattens filenames is explained in \[\[github-wiki-sync\]\].
- [Restore the legislation artifacts](restore-the-legislation-artifacts.md) — Copy the pipeline's artifact tree, or one root of it, out of the backup bucket and into a directory you name. The task never guesses the directory and refuses to write the live tree; \[\[legislation-artifact-backup\]\] holds the reasoning.
- [Run the model quality eval](run-the-model-quality-eval.md) — The eval measures whether a candidate model's answers to Sway's own bill prompts are any good. It runs only on a machine that holds the local corpus. It cannot run on a fresh clone, and it cannot run in continuous integration.
- [Run the stack locally](run-the-stack.md) — The development environment runs entirely under \`dip\`. SQLite databases live in the \`sway_storage\` Docker volume, and \`config/boot.rb\` blocks Rails from booting on the host, where it would open a different, empty \`storage/\`.
- [Running the browser error reporting spec standalone](run-browser-error-reporting-spec.md) — \`spec/system/browser_error_reporting_spec.rb\` checks that a real error reported from a real browser really arrives at the local error collector — no Ruby-side stub is on the path, so this is the only honest check.
- [Running the live Claude adapter integration spec](run-claude-adapter-integration-spec.md) — \`spec/integration/llm/claude_adapter_integration_spec.rb\` is skipped by default.
- [Scope spec helper types](scoping-spec-helper-types.md) — Extract duplicate spec helpers from top-level example groups into named support modules with explicit RBS signatures to eliminate global Object pollution and prospective method collisions.
- [Submit the mobile app to the stores](submit-the-mobile-app.md) — Sway's phone app reaches the App Store and Google Play from one operator's machine. Several values cannot exist until the store records do, so the order is fixed: records first, then the values they yield, then builds.
- [Troubleshoot deploys](troubleshoot-deploys.md) — How to resolve common deployment failures.
- [Use your own secret store](use-your-own-secret-store.md) — Point the deploy at a secret store other than Bitwarden, or at plain environment variables. The settings are listed in \[\[settings-and-secrets#Secret store settings\]\]; a setup that sets none of them keeps using Bitwarden.
- [Verify operational visibility](verify-operational-visibility.md) — How an operator verifies Sway system health using the consolidated verification script, inspects New Relic APM metrics, and configures Cloudflare Health Checks for external availability alerting.
<!-- lat:index:end -->

## Using a recipe

Each guide is self-contained; this is only the order to approach an unfamiliar one in.

1. Read the guide's opening paragraph for the constraint it works around.
2. Follow the numbered steps without reordering them — several depend on the step before.
3. Run the check the guide names at the end before treating the task as done.
