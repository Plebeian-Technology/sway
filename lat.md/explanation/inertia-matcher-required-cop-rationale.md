---
lat:
  mode: explanation
---

# Why the Inertia matcher-required cop rarely false-positives

`RuboCop::Cop::Sway::InertiaMatcherRequired` (`lib/cops/rspec/inertia_matcher_required.rb`) flags a request spec example when it asserts on a component's Inertia props (`inertia.props`.

`RuboCop::Cop::Sway::InertiaMatcherRequired` (`lib/cops/rspec/inertia_matcher_required.rb`) flags a request spec example when it asserts on a component's Inertia props (`inertia.props`, `have_props`, `have_exact_props`, `have_deferred_props`) but never pins the component name with `render_component`. Without that pin, a controller that renames its component — or swaps in a different one entirely — still passes the prop assertions, and the wrong-component bug ships without any test failing.

## Why this rarely fires falsely

Static analysis precision ensures the RuboCop matcher flags only controller actions with genuine render-inertia mismatches.

- JSON / mobile-bearer specs parse `response.body` directly and never call
  the `inertia` helper, so they are never matched.
- `have_flash` / `be_inertia_response` are not triggers — flash and
  response-shape assertions legitimately appear without a component pin, for
  example after a redirect.
- Specs that genuinely span components (shared `inertia_share` data) assert
  `have_props` with no single owning component. Exclude those files in
  `.rubocop/rspec.yml` rather than pinning an arbitrary component.

See the cop's `@example` block for the exact bad/good spec shapes it flags.

## Why flagging works per top-level group

`on_block` flags the file's outermost `RSpec.describe`, not any nested `describe`/`context` inside it.

That is the low-noise signal that matters — a request spec inspecting a component's props without pinning the component name even once. A single `render_component` call, anywhere in the file, clears the whole file, so sibling create/flash/error sub-blocks are not over-flagged just because a neighboring block happens to assert props first.

`:context` is included alongside `:describe` in `top_level_group?` so a top-level `RSpec.context` (an alias of `describe`) is not silently skipped.

## Known limitation: shared examples are not inspected

Prop assertions inside `shared_examples`/`shared_context` blocks are not inspected, because those blocks are not example groups themselves.

Prop assertions inside `shared_examples`/`shared_context` blocks are not inspected, because those blocks are not example groups themselves — they get mixed into whichever group includes them, and a group that pins the component elsewhere would make flagging the shared block on its own a false alarm.

## Why matcher names are written literally in the node pattern

[[lib/cops/rspec/inertia_matcher_required.rb]] writes `{:have_props :have_exact_props :have_deferred_props}` directly inside the `asserts_inertia_props?` `def_node_search` pattern.

A bareword constant inside a RuboCop AST node pattern matches a `const` node in the parsed source rather than interpolating the Ruby constant.
