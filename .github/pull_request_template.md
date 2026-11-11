<!-- Conventional-commit style title, e.g. fix(security): scope set_position to URL org -->

## What & why

<!-- What changed and why. Link the issue it addresses. -->

## Merge checklist

- [ ] All CI workflows green on this PR (rspec, vitest, typescript, oxlint, CodeQL; mobile-test if `mobile/**` changed)
- [ ] Behavioral changes ship with the spec that would have caught the bug (same commit)
- [ ] `sig/` RBS updated alongside backend changes; `dip run steep` clean
- [ ] No `.oxlintrc.json` changes, no new gems where a Rails 8 built-in exists
