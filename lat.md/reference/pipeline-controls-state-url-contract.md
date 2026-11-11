---
lat:
  mode: reference
---

# Pipeline controls state: URL prop and param contract

`usePipelineControlsState` (`app/frontend/components/admin/creator/pipeline-controls/usePipelineControlsState.ts`) syncs pipeline-controls state to the URL.

- This documents the two lists it keeps for that job and the traps around them.

## Props requested on a partial reload

`PIPELINE_CONTROLS_ONLY_PROPS` is `["selected_stages", "download_missing_assets", "pipeline_preview"]` — every prop this hook asks the server for when it pushes a new URL, leaving the rest of the page alone.

- The old restart confirmation dialog and the split restart menu no longer exist, so their props are not in this list — restart is a plain button now. `download_missing_assets` was added to carry that toggle's state in the URL.

- **`bill_id` is left out on purpose**, even though the server does return it. The bill lives in the PATH, not in the query — `/admin/bill_creator/:id/<tab>` — and `BillCreatorShell`'s `onBillChange` deliberately does not repeat the id in a `?bill_id=` parameter. The delayed update this hook issues keeps the path it is already on. Since `bill_id` only ever comes from the address, and nothing changes it without a full navigation, the server holds no newer value that needs to come back through this partial reload. If some future button resets the bill picker without changing the address, add `"bill_id"` to `PIPELINE_CONTROLS_ONLY_PROPS` (the picker itself is still to be built).

- **`replace: true` does not preserve the query string.** An earlier version of this comment credited it with doing so. It does not: `replace: true` only chooses `history.replaceState` over `pushState`, and has nothing to say about parameters. What keeps the rest of the query string is `currentAddressWithout`, called at the top of `flushUrlPush`.

- `flushUrlPush` starts from the address on screen, minus the two parameters it owns, rather than from the bare path. Starting from the bare path dropped everything else in the query — including `?run_id=`, which is the whole point of the link the summary tab's failure alert draws, and which `RunSelector` reads straight out of the address to decide whether it is showing a pinned run. The first stage tick unpinned the run and snapped that dropdown back to "Latest run (auto)" while the panel below still showed the pinned run.

## Query params this hook owns

`PIPELINE_CONTROLS_URL_PARAMS` is `[SELECTED_STAGES_PARAM, "stages", "download_missing_assets"]` — the query parameters this hook decides for itself.

- Everything else in the address is some other control's business and is carried through unchanged by `currentAddressWithout`.

### The legacy stages fallback

Both `compute_pipeline_controls_state` and the preview builder in `bills_controller.rb` read `params[:selected_stages] || params[:stages]`.

- The controller keeps that fallback on purpose, for old bookmarked addresses, and request examples pin it.

- Owning only the current name (`selected_stages`) in `PIPELINE_CONTROLS_URL_PARAMS` left the legacy name (`stages`) on the address free to override every later answer: selecting the default stage set (`DEFAULT_STAGE_KEYS`, every stage except `summarize-bill`) is expressed by sending nothing, so on an address carrying `?stages=fetch-bills` the server fell through to the legacy name and answered with that one stage — unticking the boxes the operator had just ticked. This is the same defect shape as a separate bug in this same file's empty-selection handling, on the other spelling. Nothing in the app writes `?stages=` today, so it takes a bookmarked or shared address to reach — which is exactly the input the fallback exists for.

### Why an empty stage selection is expressed in the address, not in data

Leave out values that are empty or already the default, so the URL stays short. Rails uses the same defaults.

- NO STAGES IS SAID IN THE ADDRESS, not in `data`, because Inertia pushes one query pair per array item and an empty array pushes none — `data.selected_stages = []` reached Rails as an absent parameter, and `compute_pipeline_controls_state` reads absent as `DEFAULT_PIPELINE_STAGE_KEYS` (every stage except `summarize-bill`). Unchecking the last box ticked the default stages back on. See `addressWithEmptyList` for why the address rather than an empty string.

- The default is on, matching the database column's default, so `download_missing_assets` goes into the URL only when the operator has switched it off.

### Why both fields are re-sent on every push, not only the one that changed

Both fields go along on every change, not only the one that changed.

- `pendingValuesRef` is filled in once when this mounts and then patched one field at a time, so an update that touched only the toggle sent the stale mount-time list of stages with it, undoing a change to the stages the server had already sent back. Passing the changed field plus the current value of the other keeps the ref up to date.

### usePipelineControlsState.test.ts notes on the empty stage selection

This example used to read `visitData().selected_stages` and assert it was `[]` — the value the hook handed the router, not the value the router sends.

- Inertia pushes one query pair per array item, so an empty array pushed none: the parameter never left the browser, Rails read an absent `selected_stages` as the default stage set, and unchecking the last box ticked the default stages back on. The example was derived from the thing it was meant to police, so it passed whatever the serializer did.

- The address is what these read instead. Everything in it reaches the server whatever the data does: Inertia merges data OVER the href's query and keeps the pairs the data does not name, and with no data at all it leaves the href alone.

### usePipelineControlsState.test.ts notes on keeping the rest of the query string

This visit used to start from `window.location.pathname`, and Inertia lays a visit's `data` over the query of the href it is given — so a bare path had nothing to lay it over and dropped every other parameter.

- The one that mattered is `?run_id=`: it is the whole point of the link the summary tab's failure alert draws, it is what LegislationPipelineRunSourcing reads to pick the surfaced run, and RunSelector reads it straight out of the address to decide whether it is showing a pinned run. So the first stage tick unpinned the run and snapped that dropdown back to "Latest run (auto)" under a panel still showing the pinned run.

- Every example in that describe block reads the URL the router was handed. The hook's own state cannot answer this question — the defect was invisible in it.

- The other side of the same wire: because Inertia's merge KEEPS a parameter the data leaves out, an address that already carries a stage list would hold onto it when the operator selects the default stage set — the state the hook deliberately expresses by sending nothing. Selecting the default stages has to clear the parameter, not inherit the old one.

### usePipelineControlsState.test.ts notes on the legacy ?stages= name

The same wire again, on the OTHER name the server reads for this one setting.

- bills_controller.rb reads `params[:selected_stages] || params[:stages]` wherever it needs the stage list, and keeps the legacy spelling for addresses bookmarked before the rename; spec/requests/admin/bills_pipeline_controls_state_spec.rb pins it.

- Selecting the default stage set is expressed by sending nothing at all, so on an address still carrying `?stages=fetch-bills` the server fell through to the legacy name and answered with that one stage. The prop changed, the hook dropped its pending value, and every box the operator had just ticked unticked itself.

- The address is what these read, for the reason the whole file gives: the hook's own state cannot see a parameter it never named.

- Written as a parameter boundary rather than as a substring: "selected_stages=" contains "stages=", so a plain toContain check could not tell the two names apart and would pass on the wrong one.

### Why the param name is a named constant

`SELECTED_STAGES_PARAM` is written twice in the source file — once in the list passed to the address remover, once in the argument passed to the writer (`addressWithEmptyList`).

- Renaming one spelling and not the other would leave the writer setting a parameter the remover no longer strips from the address, which is the one arrangement that makes Rack refuse the whole request outright.
