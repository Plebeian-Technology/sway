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

Timing starts immediately before triggering `run.mark_succeeded!`, read from the wall clock. Timing ends when an in-browser `MutationObserver` registers the DOM transition to tone `success` and text `succeeded`, also read from the wall clock. Samples across warm iterations are aggregated into summary metrics (minimum, maximum, mean, median, standard deviation) and recorded to `tmp/measurements/cable_convergence.json`.

### Why the fastest sample is judged

The spec asserts that the fastest of its samples is under 500ms. It records the median but does not assert it, because the median measures the machine's load as much as the code.

The test environment runs the in-process `test` cable adapter, which has no Solid Cable table to poll. What the spec times is therefore the second half of the one-second budget alone: frame transport, the partial reload, the controller and the React commit. That half is allowed 500ms.

CPU contention can only add time to a round trip; it never removes any. The fastest sample is the one contention touched least, so it is the closest available estimate of the code's own cost. Alone, medians run at 60–105ms and the fastest sample at about 50ms. Under the fifteen-lane `dip run verify` the median reached 899ms with one sample at 1400ms. With twenty to forty busy loops on ten cores, medians reached 1020ms while the fastest sample stayed between 240 and 494ms.

A regression that adds a fixed delay to every round trip — a debounce on the received handler, a second serial request, a wait on the 15-second poll — raises the fastest sample by the same amount, so the assertion still catches it. A regression to the poll fallback fails sooner than that: each sample must converge inside a five-second observation window, and the page's poll first fires fifteen seconds after mount.

Five samples are always taken. More are taken, up to fifteen, only while none of them has landed under the budget, so an idle machine pays nothing extra and a loaded one gets more chances at an uncontended moment.

### Why the end time is read in the browser

The end timestamp is `Date.now()` inside the observer callback, not a Ruby clock read after the WebDriver call returns. The WebDriver return is test machinery, and under load it added hundreds of milliseconds to the old figures.

Ruby and headless Chromium run on the same machine and read the same wall clock, so the two timestamps subtract cleanly. The spec checks that the difference is never negative, which would mean the browser was reading a different clock.

### Why the harness waits for the server-side subscription

Before each status change the spec waits until the cable server has registered a subscriber for the run's broadcasting. A broadcast sent before that is dropped, and the sample then times out.

An earlier fixed 150ms pause stood in for this wait. It was long enough on an idle machine and not guaranteed under load. The subscriber map entry is added on the cable server's event loop before the subscription is confirmed to the browser, so its presence means a broadcast will reach the socket.
