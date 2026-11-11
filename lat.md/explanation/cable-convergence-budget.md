---
lat:
  mode: explanation
---

# Cable convergence budget

The real-time convergence budget bounds the elapsed duration between Rails committing a state change and the browser DOM reflecting the change to one second across the running stack.

## ActionCable convergence measurement

An end-to-end browser system spec measures live ActionCable broadcast-to-DOM round trips on the admin pipeline runs surface using an in-browser MutationObserver to avoid Capybara polling distortion.

The convergence promise requires that when Rails learns of a pipeline state change, the browser DOM reflects the update within 1.0 second. This budget splits into two halves: up to 500ms allocated to Solid Cable SQLite table polling (`polling_interval: 0.5.seconds`), and 500ms allocated to WebSocket frame transport, Inertia partial reload HTTP round trip, controller rendering, and React DOM commit.

Static checks in `spec/config/cable_spec.rb` confirm that `polling_interval` is configured below half the budget, ensuring configuration leaves room to keep the promise. However, inspecting a configuration file does not measure execution time; verifying the promise requires active timing in a live browser.

The measurement harness in `spec/system/cable_convergence_spec.rb` evaluates this SLA by driving headless Chromium against the `/pipeline_runs` history surface. The spec avoids two measurement traps:

First, it does not gate on UI elements driven by client-side `useForm` state, which update optimistically on click before contacting the server. The pipeline runs index renders status badges strictly from server-provided Inertia props.

Second, it does not wait on the absence of transient indicators such as `#nprogress`. Because Capybara's `have_no_css` passes immediately before a progress bar attaches, asserting on an absence would sample before the response lands. Instead, the harness observes the positive mutation of the target row's badge.

Timing starts immediately before triggering `run.mark_succeeded!` using `Process.clock_gettime(Process::CLOCK_MONOTONIC)`. Timing ends when an in-browser `MutationObserver` registers the DOM transition to tone `success` and text `succeeded`. Samples across warm iterations are aggregated into summary metrics (minimum, maximum, mean, median, standard deviation) and recorded to `tmp/measurements/cable_convergence.json`.
