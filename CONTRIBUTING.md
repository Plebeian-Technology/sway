# Contributing to Sway

Thank you for helping. This page is short on purpose.

## Ways to help

- Report a bug or ask for a feature: [open an issue](https://github.com/Plebeian-Technology/sway/issues). Say what you did, what happened, and what you expected.
- Fix a bug or add a feature: open a pull request.
- Add your city, region or country: see the README section on adding a locale.

Found a security problem? Do not open an issue. Follow [SECURITY.md](SECURITY.md).

## Before you write code

1. Open an issue first for anything bigger than a small fix, so we can agree on the approach.
2. Set up the app with the README's Development section. Backend Rails services and databases run under Docker via `dip`.
3. Set up the host toolchain below so you can run frontend tests, linting, type checks, and pre-commit hooks directly on your machine.
4. Read `CLAUDE.md`. It describes the architecture and the code style, for people and for AI tools alike.

## Contributor host toolchain

While backend Rails services and databases run in Docker, several lint, type-check, and unit-test lanes run directly on your host machine for speed.

### 1. Pinned Runtimes & Package Managers

* **Ruby:** Version pinned in [`.ruby-version`](.ruby-version). Install via your version manager (e.g. `mise`, `asdf`, `rbenv`, `chruby`).
* **Node.js:** Version pinned in [`.node-version`](.node-version).
* **pnpm:** Installed globally (e.g. `corepack enable` or `npm install -g pnpm`).
* **gitleaks:** Required by the pre-commit hook and secret scanning (`brew install gitleaks` or package manager equivalent).

### 2. Install Host Dependencies

Install the host gems and JavaScript dependencies separately from the Docker containers:

```bash
# Ruby gems for host tools (rubocop, steep, rbs)
bundle install

# Web and mobile frontend dependencies
pnpm install
```

### 3. Verification & Quality Commands

Run these checks on your host:

```bash
# Ruby lint & types
bin/rubocop                                        # Standard Ruby
bundle exec rbs validate                           # RBS signature validation
bundle exec steep check --severity-level=information  # Steep typecheck via Bundler

# Frontend lint & types
pnpm lint                                          # oxlint (JS/TS)
pnpm fmt:check                                     # oxfmt (formatting check)
pnpm exec tsc                                      # TypeScript typecheck
dip run vitest                                     # Frontend unit & component tests

# Mobile app checks
pnpm lint:mobile                                   # Mobile oxlint
pnpm --dir mobile run typecheck                    # Mobile TypeScript typecheck
pnpm --dir mobile test                             # Mobile Jest tests

# Secret scanning
bin/secret-scan.sh staged                          # Scan staged changes with gitleaks

# Parallel gate (requires Docker running)
dip run verify                                     # Runs all host and Docker verification lanes
```

## Making a pull request

1. Fork the repository and branch from the default branch.
2. Keep each pull request to one change. Small pull requests get reviewed faster.
3. Add or update tests. A behaviour change ships with the test that would have caught the bug.
4. Run `dip run verify` before you push. It runs every test suite and lint in parallel; the focused commands are listed in the README.
5. Write commit messages in the [conventional commits](https://www.conventionalcommits.org/) style, for example `fix(bills): keep the sponsor when a vote is missing`.
6. Fill in the pull request template. Maintainers review once CI is green.

## Code style

- Ruby: Standard Ruby (`bin/rubocop`), double quotes, RBS signatures in `sig/` kept in step with the code.
- TypeScript: `oxlint` and `oxfmt`, double quotes, four-space indent.
- Comments state facts. Reasons and design decisions go in `lat.md/`.
- The maintainers track work in a private tracker whose issues cite the `lat.md/` sections behind each change; nothing you write needs to reference it.

## License

Sway is licensed under the AGPL-3.0-or-later. By contributing you agree that your contribution is licensed the same way.

## Conduct

Be kind, be patient, and assume good faith. Maintainers may close or lock discussions that are not.
