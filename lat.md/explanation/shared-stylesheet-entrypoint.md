---
lat:
  mode: explanation
---

# Shared stylesheet entrypoint

The application stylesheet is its own Vite entrypoint rather than an import inside a JavaScript entrypoint, because a stylesheet imported by two JS entrypoints stops being linked on any page at all.

`app/frontend/entrypoints/application.css` is a two-line file that imports `app/frontend/styles/application.css`. Both `application.html.erb` and `public.html.erb` reach it through `vite_stylesheet_tag 'application'`.

## Why an import inside a JavaScript entrypoint is not enough

`rails_vite`'s `vite_typescript_tag` emits `<link rel="stylesheet">` tags from the `css` array on that entry's own node in the build manifest, and Rollup decides what goes in that array.

A CSS module reachable from exactly one entrypoint is attributed to it, and the array is populated. A CSS module reachable from two entrypoints is a shared dependency, so Rollup hoists it into a shared chunk and attributes the emitted stylesheet to that chunk instead. Both entries are then left with an empty `css` array, and the helper has nothing to emit.

The stylesheet is still built, still hashed, and still served — it is simply never referenced by any page.

## What a shared stylesheet breaks

A single entrypoint can import the stylesheet safely. A second entrypoint, such as `public.tsx` for the `/sms`, `/privacy` and `/terms` disclosure pages, that imports the same stylesheet makes it a shared dependency.

Rollup then moves the Tailwind output into a shared chunk such as `assets/pageResolver-*.css`, both entries lose their `css` arrays, and the deployed pages carry no stylesheet link. The markup still has its Tailwind class names with nothing defining them: the homepage computes the browser's default serif `font-family` and reports almost no CSS rules.

Nothing fails. The build succeeds, every asset returns 200, and the only signal is a browser-side `Unable to preload CSS` error.

## Why a stylesheet entrypoint cannot regress the same way

An entrypoint is a build input in its own right, so it is never a shared dependency of something else and never hoisted into a shared chunk.

Its manifest node carries its own `file`, which `vite_stylesheet_tag` resolves directly rather than inferring it from a JavaScript entry's dependency graph.

The number of JavaScript entrypoints that want the stylesheet then stops mattering, which is the property the previous arrangement lacked — it was correct only while exactly one entrypoint imported it.

## Why the regression guard counts CSS rules recursively

`CSSStyleSheet.cssRules.length` counts only a sheet's immediate children, and Tailwind CSS 4 wraps its output in `@layer` blocks, so a shallow count of `/`'s stylesheets stays structurally small no matter how healthy the build is.

`spec/system/stylesheet_is_linked_spec.rb` is the guard for the missing-link failure. A shallow count cannot serve it, because Tailwind CSS 4's `@layer theme`, `base`, `components`, `utilities`, its `properties` layer, and its standalone `@property` rules mean a `@layer` holding a thousand nested rules counts as one. A healthy build (`dip run rspec`'s test build) gives only a few hundred top-level rules across the linked stylesheets and inline style blocks on `/`.

The guard instead walks each stylesheet's rules recursively, summing every rule at every nesting depth, which is what "how much CSS actually applies" means once layers are involved. Against that same build the recursive count is far higher when healthy than when the `application.css` link is removed to simulate the original regression. The guard's threshold, 500, sits with real headroom on both sides of the recursive measure.
