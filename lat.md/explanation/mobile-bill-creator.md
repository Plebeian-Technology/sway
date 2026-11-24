---
lat:
  mode: explanation
---

# Mobile bill creator

How the phone app opens the admin bill creator: the bill picker, the screen that loads one bill per tab, the five tab files and the section components they render.

The web bill creator under [[app/frontend/components/admin/creator]] is the behaviour the phone matches. Its components use Radix, Inertia hooks and the DOM, so the phone cannot import them and ports each part as its own React Native component.

## The bill picker

[[mobile/src/screens/admin/billCreator/BillPickerScreen.tsx#BillPickerScreen]] lists the bills of the current locale, filters them as the admin types and opens one in the bill creator.

The hub tool id `bill_creator` maps to the `AdminBillPicker` route ([[mobile-admin-area#The tool map]]). [[mobile/src/hooks/admin/useBillPicker.ts#useBillPicker]] fetches `GET /admin/bill_creator/new` and reads its `bills` prop, the list the web picker shows. [[app/controllers/bills_controller.rb#BillsController#new]] answers that page through `render_inertia_or_json`, so a mobile request gets JSON and the web still gets the Inertia page. A mobile request that names no tab gets only `bills` ([[mobile-bill-creator#Each tab gets only its own props]]).

The search field keeps a bill when its external id or its title contains the typed text, ignoring case. The web picker also matches the sponsor, status, chamber and category, and offers four sort orders; the phone keeps the server's Newest order. Each row shows the external id with the title below it. A New bill row sits above the list and stays visible while a search matches nothing.

Pressing a bill pushes `AdminBillCreator` with that bill's id. Pressing New bill pushes it with `billId: null`.

## The bill creator screen

[[mobile/src/screens/admin/billCreator/BillCreatorScreen.tsx#BillCreatorScreen]] shows one bill, or a new one, with a `SegmentedControl` for the tabs Creator, Schedule, Pipeline, Summary and Positions.

The screen opens on the Creator tab. [[mobile/src/hooks/admin/useBillCreator.ts#useBillCreator]] takes the bill id and the tab, and fetches the tab's own path: `GET /admin/bill_creator/:id/<tab>` for a saved bill, which [[app/controllers/bills_controller.rb#BillsController#edit]] answers as JSON, and `GET /admin/bill_creator/new?bill_creator_tab=<tab>` for a new one. Changing the tab fetches again. The hook follows `useBill`: state plus an abort guard, returning `data`, `loading`, `error` and `refresh`, and nothing enters the offline cache.

The header shows the bill's external id and title from the loaded `bill` prop, or "New bill". A failed request shows the server's message in an `EmptyState`, and pull to refresh reloads the current tab.

### A tab never sees another tab's props

Each tab may receive a different set of props from the server, so the hook clears its data when the bill or the tab changes and the screen shows a spinner until the new answer arrives.

A tab therefore renders only from the answer to its own path. The hook takes an optional query object that joins the path, and a change of query alone fetches again without clearing the data, so a section keeps its open state while it asks for more ([[mobile-bill-creator#Sections#The summary revisions section]]). Pull to refresh keeps the current data on screen, because the tab does not change, and only a pull shows the spinner: a background refresh, such as the pipeline tab's poll, reloads without it.

## Each tab gets only its own props

For a mobile request, the bill creator answers with only the props the requested tab reads, listed per tab in [[app/controllers/bills_controller.rb#BillsController#BILL_CREATOR_TAB_PROPS]].

The web tabs poll every five seconds, and a mobile tab polls its own path the same way. The web page builds every tab's props on each request, and the omission header ([[lazy-inertia-props#Mobile JSON omission is an explicit request]]) drops only a few named optional props. Without the map, every poll would rebuild the whole creator: the vote-entry roster, every organization, the activity log and the fetched-bills scan of the disk. [[app/controllers/bills_controller.rb#BillsController#mobile_bill_creator_tab_props]] slices the prop hash before resolution, so a prop outside the tab's list never runs. Web requests keep every prop.

Each list comes from the web components that tab renders. [[app/frontend/components/admin/creator/BillCreatorShell.tsx#BillCreatorShell]] picks one root component per tab, and the list holds the page props read anywhere below that root:

- Every tab gets `bill` and `bill_id`.
- Schedule adds `bills`, because its calendar and sidebar place every bill of the locale on their dates.
- Creator and Positions both render the organizations panel, so both carry `organizations` and `tab_key`, which the panel sends back on save.
- Creator also carries `news_articles`, which the web reads only on its Summary tab, because the phone's summary editor sits on the Creator tab and lists the citable articles ([[mobile-bill-creator#Sections#The bill fields section#Declaring news evidence]]).
- Pipeline carries the keys that [[app/controllers/bills_controller.rb#BillsController#edit]] adds outside the shared prop builder: the activity log, the artifact mirrors and the fetched bills. The web pipeline poll list also names `testimony_claimed_affiliations`, but nothing on that tab reads it, so the mobile list leaves it out.
- Pipeline also carries `legislation_pipeline_run`, the run the web progress panel shows. The web gets it as a shared prop ([[legislation-pipeline-run-sourcing-concern]]), and mobile JSON holds only the action's own props, so [[app/controllers/bills_controller.rb#BillsController#mobile_bill_creator_tab_props]] adds the shared run props before it slices.
- Pipeline also carries `recent_pipeline_runs` for the run selector, and `stale_pipeline_run_count` and `orphan_pipeline_run_count` for the cleanup buttons ([[mobile-bill-creator#Sections#The pipeline cleanup section]]). All three come from the same shared run props.
- Summary carries `review_draft_revision`, which reads the `draft_revision_id` query parameter, so a summary request still answers the draft named in its address.
- Summary also carries `active_legislation_pipeline_run`, from the same shared run props, because the web summary view keeps Regenerate off while a clean-testimony run covers the bill ([[mobile-bill-creator#Sections#The summary generation section]]).
- Summary also lists `summary_prompt`, which the server builds only for a request that asks for it ([[mobile-bill-creator#Sections#The summary generation section#Preparing the summary prompt]]). Every other summary request, the poll included, answers without it.
- Summary also lists `summary_revisions`, which the server builds only for a request that asks for it ([[mobile-bill-creator#Sections#The summary revisions section]]).
- Summary also lists `summary_source_documents`, which the server builds only for a request that asks for it ([[mobile-bill-creator#Sections#The summary sources section]]). The ledger's counts, `summary_sources`, are small and ride every request.
- Summary reads the category override's data from props the list already carried: `active_categories`, `max_active_categories_per_bill` and, inside `bill`, `override_categories` and `bill_llm_provisioning` ([[mobile-bill-creator#Sections#The category override section]]).
- Positions also carries `active_legislation_pipeline_run`, from the same shared run props, because the web's draft cards keep Approve off while a clean-testimony run covers the bill ([[mobile-bill-creator#Sections#The draft positions section]]).
- Positions also lists `testimony_campaign_letters`, which the server builds only for a request that asks for it ([[mobile-bill-creator#Sections#The campaign drafts section#Serving the letter text to the phone]]).

[[app/controllers/bills_controller.rb#BillsController#new]] applies the same lists to a new bill. With `bill_creator_tab=<tab>` it answers that tab's keys, less any key a new bill has no builder for. With no tab, or a name the map lacks, it answers [[app/controllers/bills_controller.rb#BillsController#BILL_PICKER_PROPS]], which is what the picker reads. The other props the web marks optional and never builds for mobile, such as the public testimony letters, stay absent whatever the tab.

A mobile section that needs another prop adds the key to its tab's list.

## The tabs

Each tab is one file in [[mobile/src/screens/admin/billCreator/tabs]], and the screen picks the file for the selected tab from a fixed map.

The screen passes every tab the same props, [[mobile/src/hooks/admin/useBillCreator.ts#BillCreatorTabProps]]: the bill id (`null` for a new bill), the loaded data and `refresh`. A tab reads only the props it needs. Every tab file starts as an `EmptyState` saying the tab is not on mobile yet.

## Sections

A section is one part of a web tab, ported as a component in `mobile/src/components/admin/billCreator/` and rendered by its tab file.

Porting a section adds its component to the tab file and a short section to this document describing it. Writes go through [[mobile/src/hooks/admin/useAdminMutation.ts#useAdminMutation]] ([[mobile-admin-area#Admin writes]]).

### The bill fields section

[[mobile/src/components/admin/billCreator/BillFieldsSection.tsx#BillFieldsSection]] ports the bill fields of the web Creator form, plus the shell's locale selector. The Creator tab renders it.

It edits the locale, external id, external version, title, link, sponsor, chamber, status, the introduced and vote dates, both roll-call numbers and the summary. The audio fields belong to their own section. The web form also shows a Withdrawn On date, but the bills table has no such column and the controller does not permit it, so the phone leaves it out.

The locale list is the bootstrap's `sway_locales`, the same declared locales the web's admin selector offers. A saved bill starts in its own locale, a new one in the app's current locale. The chamber starts at the bill's chamber or the locale's default, stays fixed when the locale declares one chamber, and resets to the new default when the admin picks another locale. The Senate vote date is disabled for a locale with chambers but no Senate. The sponsor list is the one the tab loaded, so it follows the bill's locale (or the app's, for a new bill) rather than the locale picked on screen, as the web's does for a saved bill.

Saving refuses locally, with the web's messages from [[app/frontend/components/admin/creator/hooks/useBillFormSubmit.ts#useBillFormSubmit]], when the locale, status, chamber or sponsor is missing. A date typed in any shape but YYYY-MM-DD is also refused; the web's date input cannot produce one. The body matches the web's: every field, `sway_locale_id`, `active` (the bill's value, or true), the declared `news_usage` with an empty `source_uses`, and each date as midnight UTC. A new bill goes to `POST /bills`, a saved one to `PATCH /bills/:id`; the web sends `PUT`, which reaches the same action.

[[app/controllers/bills_controller.rb#BillsController#create]] and [[app/controllers/bills_controller.rb#BillsController#update]] answer every redirect branch through `respond_after_write` ([[surfaces#Dual-rendered JSON]]). The phone gets the saved bill through [[app/serializers/bill_resource.rb#BillResource]], or a 422 whose field errors appear under their fields. The web keeps its redirects.

After a save the form shows the server's copy of the bill and "Bill saved.". A new bill then switches the screen to its id, which loads the saved bill's tab; an update reloads the tab so the header shows the new title.

#### The summary field

The summary editor is a field of this form, as on the web's [[app/frontend/components/admin/creator/fields/SummaryField.tsx#SummaryField]], so the bill save carries it. The bill model requires a summary, so a new bill needs one.

The field starts at the bill's published summary and sends the text untrimmed. The server publishes a summary only when the text differs from the stored one, and a trimmed copy would differ for a summary that ends in a newline.

A new bill's summary goes in with the rest of `POST /bills`; a blank one comes back as the model's "can't be blank" under the field. On a saved bill, [[app/controllers/bills_controller.rb#BillsController#update]] sends a changed summary through [[app/services/manual_news_summary_publication_service.rb#ManualNewsSummaryPublicationService]] with the news usage the admin declared ([[mobile-bill-creator#Sections#The bill fields section#Declaring news evidence]]). A refusal answers 422 with a generic message and the real reasons in `details.errors`, so the field lists each reason under the input. The same `details` also carries the publication's `status` string; the form ignores field errors while reasons are present, so that status never lands under the Bill Status choice.

The ported rules are the web's label, the required marker, the helper text, the link to the Markdown syntax guide, and a live preview drawn by the app's [[mobile-markdown-rendering#Rendering|Markdown renderer]]. The web sets no length limit and validates nothing locally, so neither does the phone.

The phone leaves out four web behaviours. The web turns `:name:` emoji shortcodes into emoji as the admin types; that table is a 100 KB JSON file behind the web's import alias. The web keeps an unsaved draft in browser storage, with the summary it was written against; the phone keeps no drafts. The web swaps in a newly published summary when the admin has not touched the text; the phone's form reads the bill once per load. The web's preview carries no AI-unreviewed notice, and the phone matches it: the Summary tab shows that notice beside the published summary ([[mobile-bill-creator#Sections#The summary generation section]]).

#### Declaring news evidence

Below the summary field, [[mobile/src/components/admin/billCreator/NewsEvidenceControls.tsx#NewsEvidenceControls]] declares whether the summary cites news reporting, as the web's [[app/frontend/components/admin/creator/llm-summary/ManualNewsEvidenceControls.tsx#ManualNewsEvidenceControls]] does.

The publication service refuses a changed summary without a declaration, and refuses a summary that links to news while declaring none ([[news-manual-evidence-ui#Manual evidence review controls]]). Before these controls the form always declared `none`, so a summary citing news, including a restored legacy draft, could not be published from the phone.

The ported rules are the web's title and help text, the two choices with their labels, `none` selected on load, and the notice shown while `none` is selected and the summary links to any host outside the web's official list (a link that cannot be parsed counts as outside). The declaration survives a save, as the web's does.

The save sends `news_usage` as declared and `source_uses` as an empty list, which is what the web's summary editor sends: it never fills the manifest. With `cited`, the server checks each news link in the prose against the bill's approved articles that carry usable text, and infers the claims from the prose itself. A refusal lists the server's reasons under the summary field ([[mobile-bill-creator#Sections#The bill fields section#The summary field]]).

The phone adds one thing. The web editor shares its Summary tab with the news articles panel, so the admin sees the articles while writing. The phone shows one tab at a time, so with `cited` selected the controls list the approved articles with text (title, outlet and selectable address), or say that none exists yet. The Creator tab's prop list gained `news_articles` for this list.

The phone leaves out the web control's unused `sourceUses`, `onChangeSourceUses` and `newsArticles` props, which render nothing, and the web editor's separate publication error banner, because the summary field already shows each reason.

### The legislator votes section

[[mobile/src/components/admin/billCreator/LegislatorVotesSection.tsx#LegislatorVotesSection]] ports the web's [[app/frontend/components/admin/creator/BillCreatorLegislatorVotes.tsx]] ledger. The Creator tab renders it below the bill fields.

Each legislator of the tab's `legislators` prop is a row, sorted by display name ignoring case, with the district line and a Former stamp when the legislator no longer serves. The row offers For, Against and Abstain, and the saved `legislator_votes` start selected. Picking one position clears the other two. A saved vote for a legislator outside the roster stays in the payload, as on the web. An empty roster shows "No legislators available for this locale yet." and no save button. The tab shows "Legislator votes refreshed at ... from ..." when the server names both a time and a source.

Save posts `bill_id` and every selected `{legislator_id, support}` to `POST /legislator_votes`, grouped For, Against, Abstain. A bill with no id refuses locally; the web names its Details and Summary tab there, and the phone has no such tab. The section keeps its selections after a save and does not reread them when the tab reloads, because the web's form behaves the same.

[[app/controllers/legislator_votes_controller.rb#LegislatorVotesController#create]] answers every redirect branch through `respond_after_write` ([[surfaces#Dual-rendered JSON]]). The phone gets 200 JSON on success. A refusal answers 422 with the message under `legislator_votes`, the key the web's `notifyServerRefusal` reads, and the section shows that message, then the server's message, then "Could not save legislator votes.". A save that skipped a legislator whose term misses the bill's date commits the other votes yet answers 422 with the web's alert, because `respond_after_write` treats any alert as a failure. The web keeps its redirects.

### The organizations section

[[mobile/src/components/admin/billCreator/OrganizationsSection.tsx#OrganizationsSection]] ports the save, rename and remove paths of the web's [[app/frontend/components/admin/creator/BillCreatorOrganizations.tsx#BillCreatorOrganizations]] panel. The Creator tab renders it below the legislator votes.

The web shows the same panel on its Positions tab, so the section takes the tab props (`billId`, `data`, `refresh`) and reads `bill.organizations`, `organizations` and `tab_key` from `data` itself. It never assumes the Creator tab.

Each organization of the bill is a row holding this bill's position: support (For when none is saved) and summary. The search field offers the locale's unselected organizations whose name contains the typed text. Create appears when the name, with spaces collapsed and case ignored, matches no selected or offered organization; a created row takes the next negative id, as on the web, so the server looks the name up within the bill's locale. Submitting the field adds the first match, or else creates the typed name. The switch sets For or Against; a saved Abstain shows as Abstain and is sent unchanged until the switch moves.

Save posts `bill_id` and every row's `value`, `label`, `support`, `summary` and `icon_url` (plus `icon_signed_id` on a row with a new upload, [[mobile-bill-creator#Sections#The organizations section#Organization icons]]) to `POST /organizations?bill_creator_tab=<tab_key>`, defaulting to `positions` like the web. The row's saved `icon_url` goes back unchanged, because [[app/controllers/organizations_controller.rb#OrganizationsController#create]] writes whatever the row sends to the organization's address. A bill with no id refuses locally with "Save the bill before saving organizations.". The rows stay as typed after a save, as the web's form does, and `refresh` reloads the tab's other props.

The create action answers both branches through `respond_after_write` ([[surfaces#Dual-rendered JSON]]). Success answers 200 JSON and the section shows "Supporting/Opposing Arguments Saved". A refusal rolls back every row and answers 422 with the web's alert as the message and the row errors under `details.organizations`, one hash per row in the order sent ([[organizations-controller#Create errors retain their row and field shape]]). The section shows the message below the rows and each row's label, icon and summary errors on that row. The web keeps its redirect, flash and Inertia errors.

Each saved row also carries Rename and Remove. Rename opens a field holding the name; Save name sends `PATCH /organizations/:id` with the trimmed name alone. A blank or unchanged name closes the field without a request. An organization belongs to every bill in its locale, so the field says so, and a created row, which has no saved organization yet, offers no Rename. On success the row shows the new name and `refresh` reloads the locale's organization list; on a refusal the field stays open with the server's message.

Removal asks first, because the web's button acts at once and a phone press is easier to mistake. Confirming sends `DELETE /organization_bill_positions/:id?bill_creator_tab=<tab_key>`, which unpublishes the position ([[organization-position-removal#Removal deactivates, it does not delete]]); the organization stays. The position id comes from the latest `bill.organizations`, not from the row, so a row saved in this session can be removed after `refresh` has reread it. A row with no saved position drops locally with no request, as on the web. A refusal leaves the row and shows the message on it.

[[app/controllers/organizations_controller.rb#OrganizationsController#update]] and [[app/controllers/organization_bill_positions_controller.rb#OrganizationBillPositionsController#destroy]] answer through `respond_after_write` ([[surfaces#Dual-rendered JSON]]). Success is 200 JSON. A refused or unknown organization answers 422 with the web's alert as the message and no field errors. The web keeps its redirects and flash.

The web's selected-organization chips, its dirty-state guard and its local draft storage stay web-only: the chips only duplicate the Remove control, and the draft cache that restores a removed row's typed text has no mobile counterpart.

#### Organization icons

Each row shows its icon, or "No icon", beside Add icon (Update icon once it has one) and, when it has one, Remove, as the web's [[app/frontend/components/admin/creator/OrgIconUpload.tsx#OrgIconUpload]] does.

Pressing Add icon opens the system file picker for images. [[mobile/src/api/directUpload.ts#directUpload]] then uploads the chosen file in the two steps the web's Active Storage client takes. It posts the blob's filename, byte size, content type and checksum to `POST /rails/active_storage/direct_uploads` through the API client, so the bearer token rides along ([[admin-only-direct-uploads-design#Why a bearer token decides identity on its own]]). It then sends the file's bytes in a `PUT` to the URL the server returns, with exactly the headers the server returns and no others. Those headers carry the content type and checksum the storage service checks, so they must match. The same code serves the development disk service and the production bucket, because the server names the URL either way.

Active Storage wants the checksum as the base64 of the raw MD5 digest. The file system module reports the MD5 as hex, so the helper converts it; no hashing library is needed. The helper takes a file URI, filename and content type and answers the blob's `signed_id`, so other upload fields can reuse it.

An upload changes nothing on the server until Save. The row keeps the `signed_id` as `icon_signed_id` and shows the picked file; Save stays disabled, showing "Saving...", while any row's upload runs, so a save never leaves a new icon behind. Save sends `icon_signed_id` with that row only, and [[app/controllers/organizations_controller.rb#OrganizationsController#create]] attaches the blob. Remove clears the row's `icon_url` and any `icon_signed_id`, as the web's Remove does, and Save sends the blank address. A closed picker sends nothing, and a failed upload shows its message on the row.

The file picker and file system are native modules, so a phone needs a development build made after they were added (`eas build --local`); an older build cannot open the picker.

### The paste summary section

[[mobile/src/components/admin/billCreator/PasteSummarySection.tsx#PasteSummarySection]] ports the web's [[app/frontend/components/admin/creator/PasteSummaryDialog.tsx#PasteSummaryDialog]]. The Summary tab renders it below the generation section.

A Paste summary JSON button opens a box with the web dialog's title, help text, placeholder and a collapsed Schema reference that shows [[app/frontend/components/admin/creator/llm-summary/pasteSummarySchemaExample.ts#PASTE_SUMMARY_SCHEMA_EXAMPLE]]. Validate & paste stays disabled while the box holds only whitespace. It posts the text untrimmed as `summary_json` to [[app/controllers/bills_controller.rb#BillsController#paste_summary]], which already answers mobile in JSON. The box and both buttons stay locked while the request runs.

A rejection answers 422 with `details.errors`, a list of path and message pairs. The section lists each pair, keeps the text, and clears the list when the next paste is sent. Tapping a pair focuses the box and moves the cursor to the rejected key through the web's [[app/frontend/components/admin/creator/paste-summary/resolveJsonPointerOffset.ts#resolveJsonPointerOffset]], or to the start when the key is not found. A refusal without that list, such as an offline phone or a 403, shows the server's message instead.

Success closes the box and refetches the tab, so the new draft appears in the generation section. Cancel clears the text and the errors and closes the box. The form is its own component, so closing it discards the mutation state with it. A new bill has no id to post to, so the section shows "Save the bill before pasting a summary." in place of the button.

The phone leaves out five web pieces:

- The Copy example button, because the app installs no clipboard module; the example is selectable text.
- The info popover beside the dialog title.
- The note that a summary was saved but the bill's status was not updated. The mobile answer is 200 either way, and the backend is not changed here, so the phone cannot tell the two outcomes apart.
- The per-error dismissal memory, because the phone's errors live in the open form and vanish when it closes.
- The check that the redirect landed on this bill's creator, because the phone reads the response status instead of a redirect.

### The summary audio section

[[mobile/src/components/admin/billCreator/SummaryAudioSection.tsx#SummaryAudioSection]] ports the audio controls of the web's [[app/frontend/components/admin/creator/BillCreatorSummaryAudio.tsx#BillCreatorSummaryAudio]]. The Creator tab renders it below the bill fields.

The web draws these controls inside the summary field of the Creator form, not on the Summary tab, so the phone places them on the Creator tab too. The audio is two bill fields: `audio_bucket_path`, which holds either an uploaded file's signed id or a link ([[bill-creator-summary-audio#Why this is a rebuild, and why audio_bucket_path holds either an upload or a link]]), and `audio_by_line`. The fields start from the tab's `bill`.

Upload Audio Summary (New once the field has a value) opens the system file picker for audio. [[mobile/src/api/directUpload.ts#directUpload]] uploads the chosen file and the field then shows the returned signed id, as on the web. Pasting a link into the same field is the other way to set it. A closed picker changes nothing, and a failed upload shows its message and keeps the old value.

Save Audio sends `PATCH /bills/:id` with both fields alone, each trimmed. [[app/controllers/bills_controller.rb#BillsController#update]] needs no other field. Success shows "Audio saved."; a refusal shows the server's message and each field's own error. The controller removes the previous stored file when the path changes, on the phone as on the web. An upload changes nothing on the server until Save, and Save, the upload button and both fields stay disabled while an upload or a save runs, so a save cannot send a path the upload has not yet returned.

A new bill has no id to patch, so the section shows "Save the bill before adding audio." in place of its controls. The web lets an admin set audio on a new bill, because its single form posts every field together; the phone saves the bill fields and the audio separately.

The phone leaves out four web pieces:

- The audio player and its "Audio sourced from" line, because the app has no audio playback module; the By field already shows the line.
- The upload dialog's progress bar, because [[mobile/src/api/directUpload.ts#directUpload]] reports no progress; the button reads "Uploading..." instead.
- The dialog's "For bill" and "Current file" lines, because the two fields below the button show the same values.
- The blur handler the web form passes down, which has no counterpart without a shared form.

The web's info popover for the audio field becomes a line of help text above the button.

### The schedule section

[[mobile/src/components/admin/billCreator/BillScheduleSection.tsx#BillScheduleSection]] and [[mobile/src/components/admin/billCreator/ScheduledBillsSection.tsx#ScheduledBillsSection]] port the web Schedule tab, where an admin picks the release day of the bill of the month.

The first section ports the web's selected-bill panel. It shows the bill and either a date field or, for a scheduled bill, its release day. The second ports the web sidebar: upcoming bills grouped under month headings, earliest first, then past bills and unscheduled bills. The tab needs no new props, because the picker's `bills` already carry each bill's id, external id, title and release day.

The web rules that carry over:

- A new bill cannot be scheduled. The section shows the web's message, "Save new Bill of the Month before scheduling release date."
- Schedule bill stays disabled until the field holds a real day, written `YYYY-MM-DD`, that is not before today. [[mobile/src/utils/calendarDay.ts#parseCalendarDay]] rejects overflow such as `2026-02-31` by formatting the parsed day back and comparing, as the web does ([[bill-schedule-calendar-dates#Scheduler navigation, today control, and pagination]]).
- The write sends the bare day, never an instant ([[bill-schedule-calendar-dates#Why a picked day travels as a bare day]]).
- A scheduled bill offers only Remove from schedule, which sends a null day, and the same reminder: to re-schedule, remove first.
- A day another bill holds is refused at the field, as the web marks such a day taken. Pressing a row in the lists opens that bill on the Schedule tab, as the web's Select button does.
- Upcoming means today or later by the phone's local midnight. Past bills show five at a time with the full count, and so do unscheduled bills, which start collapsed.

Both writes are `PATCH /bill_of_the_month_schedule/:id`, because the phone client has no PUT and the resource route answers both verbs. [[app/controllers/bill_of_the_month_schedule_controller.rb#BillOfTheMonthScheduleController#update]] answers through `respond_after_write`. The unique index on the release day and locale means two bills cannot share a day, and a race with another admin would otherwise raise `ActiveRecord::RecordNotUnique` and answer 500. The action rescues it and answers 422 (the web a redirect with the same message), which the section shows under the field.

The phone leaves out these web pieces:

- The month grid and the Month and Agenda toggle, because a typed day and the month-grouped list give the same information in less space. Today and the month arrows go with the grid.
- The `date` query parameter, which only carried the picked day across a reload; the phone keeps the typed day in the section while it stays mounted, and a bill switch starts a fresh field.
- The info popovers beside each heading.
- The server's list order: the phone sorts upcoming bills earliest first and past bills latest first, so the month headings read in order.
- The page-number control of the past and unscheduled lists, replaced by a Show more button.

### The pipeline stages section

The Pipeline tab's stage section lets an admin choose which pipeline stages to run and start a run with `POST /bills/run_pipeline`.

[[mobile/src/components/admin/billCreator/PipelineStagesSection.tsx#PipelineStagesSection]] ports the stage selector and the Run button of the web's [[app/frontend/components/admin/creator/BillCreatorPipelineControls.tsx#BillCreatorPipelineControls]]. The web stage list lives in a file the phone cannot import, so the section copies its labels, help lines, default set and reduced-work set. The selection starts from the tab's `selected_stages` and `download_missing_assets` props.

The web rules that carry over:

- Each stage is a checkbox row with its help line. A count reads "N of 8 selected"; Select all is disabled when every stage is ticked, and Clear all when none is.
- Download missing assets reads as ticked and is disabled while both fetch stages are ticked, with the web's "nothing to backfill" line, because the server forces it on then.
- The Run button stays disabled, with "Pick at least one stage to run.", until a stage is ticked. Its label names the bill, or all bills for a new bill, and the locale's city.
- The body matches the web's: the stages in the order they were ticked, the bill id (null for a new bill, which runs every bill of the locale), the bootstrap locale's id and the asset choice.
- The "Also required" note, its reduced-work line and the prerequisite warning come from the server's `pipeline_preview`, as on the web.

The server builds `pipeline_preview` only for a request whose address names `selected_stages`, and the tab's own request names none. The web refetches the preview with a partial reload each time the selection changes. [[mobile/src/hooks/admin/usePipelinePreview.ts#usePipelinePreview]] does the same: every change requests the tab path with the selection in its query and keeps only the preview, aborting the previous request. That request builds the whole pipeline tab, because mobile JSON has no partial reload; an admin changes the selection rarely enough for that cost. A failed preview request hides the notes, and the server still checks the run.

A queued run shows "Pipeline run queued." and refreshes the tab. A refusal shows the server's reason: `details.pipeline` for a 422, and the message naming the active run for a 409. The web shows a toast, plus a fixed "already running" alert whenever its `pipeline` error is set.

The phone leaves out these web pieces, which need the current run's controls or the stale and orphan counts that the tab does not serve: the in-flight state that disables the controls, the failure header, Force fail, the origin hint, the live-update banner, and the stuck-run and orphan-run buttons. The server refuses a second run with 409 meanwhile. The info popovers and the selection kept in the address are left out too.

[[app/controllers/bills_controller.rb#BillsController#run_pipeline]], `resume_pipeline_run` and `restart_pipeline_run` answer through `respond_after_write` ([[bills-controller-design#enqueue_pipeline_run! and render_pipeline_duplicate_run]]). A queued run answers 200 with an empty body. A refused run (no locale, a conflicting locale, a refused resume, a bad stage) answers 422 `validation_failed` with the reason under `details.pipeline`, because the web reads the same reason from its `pipeline` Inertia error. A run started while another is active still answers 409 `duplicate_run` with the active run's id.

### The pipeline progress section

The Pipeline tab's progress section shows the current pipeline run, its stage and its terminal result, refetching the tab while the run is in flight.

The tab's `legislation_pipeline_run` prop is the same run the web surfaces ([[legislation-pipeline-run-sourcing-concern]]): a run picked by `run_id`, else the newest active run, else the newest run of any status. Its `pipeline_run_stages` list each stage with its status and position. The bill's `bill_pipeline_last_failure` and `bill_pipeline_refresh` already arrive inside `bill`.

[[mobile/src/components/admin/billCreator/PipelineProgressSection.tsx#PipelineProgressSection]] ports the web's [[app/frontend/components/admin/creator/PipelineProgress.tsx#PipelineProgress]] panel and its header, running detail, error list and terminal alerts. The Pipeline tab renders it below the stage section. The web files import Radix and the page's type namespace, so the section copies their status labels, phase labels and time formats.

The web states that carry over:

- No run shows "No pipeline run yet." with the web's hint.
- The header names the status as the web's global badge does: a stage status such as "Extracting text", Queued, Running, Done, Succeeded, Partial, Failed (or "Failed — no output" for an `empty_artifact:` error) and Cancelled. A running run with bill errors adds the error count, and a run with a phase adds its label.
- An abandoned run shows the web's notice and no progress bar. Any other in-flight run shows the bar, filled to the share of bills processed.
- A running run shows its current bill, the time left, the bill count and a collapsed queue. Bill errors list under a toggle that starts open for a failed run.
- Terminal runs show the web's alerts: complete with the bills updated, succeeded, partial, cancelled with its time and count, and failed with the phase, the reason, the remedy and the failure's age and time. A failed single-bill run also lists its stages, marking each succeeded or failed stage.

The remedy text follows the web's three cases. A failed single-bill run names Resume and Restart, which [[mobile/src/components/admin/billCreator/PipelineRunActionsSection.tsx#PipelineRunActionsSection]] offers. A run over every bill names Run pipeline, for the picked bill or, on a new bill, for every bill.

The run JSON carries no `processed`, `total`, `phase`, `eta_seconds`, `errors` or `queued` today, on the web or the phone ([[pipeline-run-optional-progress-fields]]). The section reads them with the web's defaults, so a running run shows "—", "0 / ? bills" and an empty bar until the server sends them.

The phone leaves out these web pieces:

- The Cancel button of the web's page-wide run banner. The phone shows the button in the progress panel only.
- The live connection and its "Live updates paused" line, because the phone polls instead.
- The info popovers.
- The bill's `bill_pipeline_last_failure`. The web reads it only in the Summary tab's empty state, so the Pipeline tab ports nothing for it.

#### Cancelling a run

An in-flight run shows Cancel run below its progress, as the web panel does.

The button takes two taps: the first reads "Tap again to cancel" and lapses after three seconds, the second sends `DELETE /bills/legislation_pipeline_runs/:id` ([[mobile/src/hooks/useTwoTapConfirm.ts#useTwoTapConfirm]] holds the window). An abandoned run reads "Clear this run" and "Tap again to clear" instead, and uses the same endpoint, because the server cancels a run nobody carries the same way as a live one. A finished run shows no button.

[[app/controllers/bills_controller.rb#BillsController#cancel_pipeline_run_bill]] answers through `respond_after_write`. A cancelled run answers 200 with an empty body, and a run in a status that cannot be cancelled answers 422 with "Cannot cancel run in status=..." as the message, which the button shows under itself. The web redirects with the same texts as a notice and an alert.

The web asks for a second confirmation when the creator form has unsaved changes, because cancelling navigates away. The phone has no such form on this tab and leaves that dialog out.

#### Polling while a run is in flight

[[mobile/src/hooks/admin/usePolling.ts#usePolling]] calls a refresh function every interval while a condition holds, and the progress section uses it to refetch the tab every five seconds.

The hook takes three arguments: `refresh`, `active` and the interval in milliseconds. It starts a timer only while `active` is true and the screen has focus, and clears it when `active` turns false, the screen loses focus or the component unmounts. It returns nothing; the caller's `refresh` owns the request and its state. The first call comes one interval after the start, because the tab has just loaded.

The progress section polls while the run's status is in flight or the bill's `bill_pipeline_refresh` is queued or running, the same condition the web's [[app/frontend/components/admin/creator/BillCreatorPipelineLlm.tsx#BillCreatorPipelineLlm]] uses for its five-second poll. A finished run turns `active` off, so the tab stops refetching. The web pushes run updates over a live connection and polls as a fallback; the phone has no live connection here and only polls.

### The pipeline run controls section

[[mobile/src/components/admin/billCreator/PipelineRunActionsSection.tsx#PipelineRunActionsSection]] ports the Resume and Restart buttons of the web's [[app/frontend/components/admin/creator/pipeline-controls/PipelineResumeActions.tsx#PipelineResumeActions]]. The Pipeline tab renders it between the run selector and the progress section, so the remedy text's "above" is true.

The web rules that carry over:

- The buttons show only for a failed single-bill run.
- Resume reads "Resume from stage N", where N is the position of the failed stage row or, without one, the place of the run's current stage in the stage list; it reads "Resume" when neither is known. Restart reads "Restart entire run".
- Both buttons post an empty body to `/bills/legislation_pipeline_runs/:id/resume` or `/restart` and stay disabled while either request runs. Neither asks for confirmation, as on the web.
- A refusal shows the server's reason, the `pipeline` error of a 422 or the message of a 409 for a run already in flight, as the stage section does.

A queued resume or restart creates a new run, so the tab returns to the latest run and refetches. The web keeps its address pin across the redirect and relies on a page-wide banner to reveal the new run; the phone has no banner, so it follows the new run itself.

The phone leaves out the web's failure header ("Failed at stage N: ..."), which the progress section's failed alert already covers, and the "Resume of run N" origin line.

### The pipeline cleanup section

[[mobile/src/components/admin/billCreator/PipelineCleanupSection.tsx#PipelineCleanupSection]] ports the web's cleanup controls: Force fail, the stuck-run sweep and the orphan delete.

The web code is [[app/frontend/components/admin/creator/ForceFailDialog.tsx#ForceFailDialog]] and the buttons of [[app/frontend/components/admin/creator/pipeline-controls/PipelineActionButtons.tsx#PipelineActionButtons]]. The Pipeline tab renders the section after the progress section, and the tab's prop list carries the `stale_pipeline_run_count` and `orphan_pipeline_run_count` it reads.

The web rules that carry over:

- Force fail shows only while the shown run is in flight, the same statuses that give the progress section its Cancel button.
- Force fail asks the admin to type `force fail`. The confirm button stays disabled until the text matches exactly, and it posts the typed phrase to `POST /pipeline_runs/:id/force_fail`. Cancelling, or a successful fail, clears the text.
- "Remove N stuck runs" shows only when the stale count is above zero and posts to `POST /bills/sweep_stale_pipeline_runs`. The server fails only unfinished runs with no update for four hours and no background job or live summary batch, and keeps their history ([[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Stuck runs require evidence of abandonment]]).
- "Delete N orphan runs" shows only when the orphan count is above zero and sends `DELETE /pipeline_runs/orphans`. Orphans are runs queued or running for over four hours with no active worker, and the delete cannot be undone.
- A refusal shows the server's reason under the control that sent the request.

The web confirms the two bulk buttons in a dialog that names the count. The phone uses a two-tap button ([[mobile/src/hooks/useTwoTapConfirm.ts#useTwoTapConfirm]]): the first tap reads "Tap again to ..." with the count and lapses after three seconds, and the explanation the dialog carried sits under the button as a hint. Each button shows the server's result after it runs: "Cleared N stuck pipeline runs." from the sweep's count, and the orphan delete's "Removed N orphan runs." or "No orphan runs to remove.". The result stays after the counts drop to zero. The section then refetches the tab so the counts and the shown run update.

[[app/controllers/pipeline_runs_controller.rb#PipelineRunsController#force_fail]] and [[app/controllers/bills_controller.rb#BillsController#sweep_stale_pipeline_runs]] answer through `respond_after_write`. A force fail answers 200 with the failed run's summary. A wrong phrase or a run that is no longer in flight answers 422 with the `pipeline` error under `details`, as the cancel and resume refusals do. The sweep answers 200 with the number of runs it failed. The web redirects exactly as before.

The phone leaves out the info popovers and tooltips, the `back_to` parameter of the web's redirects, and the web's rule that disables Force fail while a Resume, Restart or Run request posts: on the phone those controls never show for an in-flight run.

### The run selector section

[[mobile/src/components/admin/billCreator/RunSelectorSection.tsx#RunSelectorSection]] ports the web's [[app/frontend/components/admin/creator/RunSelector.tsx#RunSelector]], which picks the run the Pipeline tab shows. The tab asks for `recent_pipeline_runs` and the server's twenty newest runs fill the list.

The web rules that carry over:

- The selector shows nothing when there are no runs.
- A pinned run shows as "Run #id · status · bill or all bills · start time". A failed run adds its age after the status. Without a pin the selector reads "Latest run (auto)", even when the newest run is the one shown.
- Choosing "Latest run (auto)" clears the pin, and the tab follows the newest run again.

The web keeps the pin in the address as `?run_id=`. The phone keeps it in the tab's state and fetches `/admin/bill_creator/:id/pipeline?run_id=N` through [[mobile/src/hooks/admin/usePinnedPipelineRun.ts#usePinnedPipelineRun]]. That response replaces the tab's `legislation_pipeline_run` and `recent_pipeline_runs`, and the progress section polls it while the pinned run is in flight. Switching bills drops the pin, as the server's redirects refuse to carry a pin across bills ([[bill-creator-run-pin-redirect-interceptor#Why it refuses to cross bills]]).

The phone shows the options in a list under a toggle, in place of the web's select element.

### The pipeline read-only panels

The Pipeline tab ends with four collapsible panels that only read: the bills of an all-bills run, the resource cache, the fetched bills on disk and the activity log. None of them offers a write on the web, so none writes on the phone.

Each panel is a component in `mobile/src/components/admin/billCreator/`: [[mobile/src/components/admin/billCreator/PerBillGridSection.tsx#PerBillGridSection]], [[mobile/src/components/admin/billCreator/ResourceCacheSection.tsx#ResourceCacheSection]], [[mobile/src/components/admin/billCreator/FetchedBillsSection.tsx#FetchedBillsSection]] and [[mobile/src/components/admin/billCreator/ActivityLogSection.tsx#ActivityLogSection]]. They port [[app/frontend/components/admin/creator/PerBillGrid.tsx#PerBillGrid]], [[app/frontend/components/admin/creator/ResourceCachePanel.tsx#ResourceCachePanel]], [[app/frontend/components/admin/creator/FetchedBillsPanel.tsx#FetchedBillsPanel]] and [[app/frontend/components/admin/creator/ActivityLogPanel.tsx#ActivityLogPanel]]. The web files import Radix, Inertia and the page's type namespace, so each section copies the labels, tier order and freshness thresholds it needs.

[[mobile/src/components/admin/billCreator/CollapsibleSection.tsx#CollapsibleSection]] gives every panel a toggle. The web remembers each panel's state in the browser and opens it by default. The phone starts every panel closed and renders nothing inside until it opens, so a long fetched-bills list or activity log never lengthens the tab or costs a render before the admin asks for it.

The panels read props the tab already serves: `legislation_pipeline_run` (its `pipeline_run_bills` and `pipeline_run_stages`), `bill_artifact_mirrors`, `fetched_bills`, `activity_log_entries`, `activity_log_next_cursor` and `activity_log_has_more`. The bills panel follows the run the tab shows, a pinned run included. The other three read the tab's own response, because a pinned-run response carries none of them.

The rules that carry over:

- The bills panel appears only for an all-bills run. Its rows list the bill being edited first, marked "This bill", then each bill with its title or external id, status, the run's current stage ("—" once the run has finished), stages succeeded out of total, and a relative start time. A run with no bills yet reads "No bills processed yet".
- The resource cache panel always lists the five tiers in the web's order: PDF, Extracted Text, Parsed Sections, Diff and Summary. A tier with no mirror reads "Not cached" with dashes; a cached tier shows its relative generation time, version and "Fresh" or "Stale".
- The fetched bills panel shows the count ("N of M bills" while filtering), a search over external id and title, and the four freshness chips. A bill fetched under seven days ago is fresh, under thirty days stale, and older very stale. A row without a bill record reads "(orphan on disk)". An empty list reads "No bill artifacts on disk yet. Run the fetch-bills stage to populate."; a filter with no match offers "Clear filters".
- The activity log shows each entry's severity, title, subject, actor ("System" without one), relative time and message, with its payload and inspect query behind a Details toggle. An empty log reads "No activity yet".

Load more follows the web: the next page of older entries comes from the same tab address with `cursor` set to `activity_log_next_cursor` ([[app/controllers/bills_controller.rb#BillsController#activity_log_entries_prop]] reads `params[:cursor]`), and the button shows while `activity_log_has_more` is true. [[mobile/src/api/routes.ts#Routes]] builds the address for a saved bill and for a new one. Mobile JSON has no partial reload, so the response is the whole pipeline tab and the section keeps only its three activity log keys. It appends the older entries to the ones the tab holds, drops any id it already shows, and takes the next cursor from the latest response. A refresh of the tab replaces the first page and leaves the older entries in place. A failed request shows its message and keeps the button.

The phone leaves out these web pieces:

- The activity log filters (subject, severity and window) and the live "Show N new entries" button fed by ActionCable. The phone always reads the server's defaults, all bills over seven days, and gets new entries when the tab polls.
- The client-side paging of ten entries, which the single growing list replaces, and the flash banner and toast for a new or failed entry.
- The Copy button for the inspect query. The text is selectable instead, because the app has no clipboard library.
- The View link on each bill row and the link on each fetched bill, which open another bill's Pipeline tab. The sections hold no navigation.
- The tooltips with full timestamps, the info popovers, and the row virtualization, which the closed-by-default panels make unnecessary for the grid but not for a very long fetched-bills list.

### The sending services section

[[mobile/src/components/admin/billCreator/SendingServicesSection.tsx#SendingServicesSection]] ports the web's [[app/frontend/components/admin/creator/SendingServicesPanel.tsx#SendingServicesPanel]]: a collapsible list of sending-service domains where the admin confirms a domain or removes its label. The tab already asks for `sending_service_domains` and `sending_service_domains_total`, so the prop lists did not change.

The web rules that carry over:

- The panel opens with the line that a sending service says only that a letter was machine-sent, never which campaign it belongs to or what it argues. A list capped below the total says "Showing the N domains with the most machine-sent letters, of T." An empty list reads "No sending-service domains yet."
- A search over the domain text filters the loaded rows, five to a page. A search with no match says so, and when the server capped the list it adds how many domains are not loaded ([[pagination#Search filters the capped list, not the full table]]).
- Each row shows the domain, sender count, bill count, the machine-sent share as a rounded percentage (zero letters count as 0%) with "N of M letters" beneath, and a stamp: CONFIRMED, PROPOSED or UNLABELED. Rows key on the numeric id, never on the domain text, because testimony submitters supply the domain ([[bill-creator-pipeline-llm-tab#SendingServicesPanel design and untrusted-domain guards]]).
- A confirmed domain offers "Remove this label". Any other domain offers "Confirm as a sending service" and "Not a sending service". Confirming sends `PATCH /sending_service_domains/:id` with `label: "confirmed"` and the bill id; both removal buttons send `label: "none"`.
- Each action first asks for confirmation with the web's wording, and a row's buttons stay disabled while its request runs.
- A refusal shows the server's `sending_service` reason under the row, with the generic message as fallback.

[[app/controllers/sending_service_domains_controller.rb#SendingServiceDomainsController#update]] answers through `respond_after_write`: 200 on success, 422 with the `sending_service` error under `details` for an unknown label. The web redirects exactly as before. Mobile JSON has no partial reload, so a successful write refetches the whole Pipeline tab.

The phone leaves out these web pieces:

- The info popover on the actions column.
- The remembered open or closed state of the panel. The phone starts it closed, like every collapsible section ([[mobile-bill-creator#Sections#The pipeline read-only panels]]).
- The page-number links of the web pagination. The phone shows Previous and Next buttons with "Page N of M".
- The toast for a refused label change, replaced by the message under the row.

### The summary generation section

[[mobile/src/components/admin/billCreator/SummaryGenerationSection.tsx#SummaryGenerationSection]] opens the Summary tab: the bill's summary status, the published summary as Markdown, and the controls that queue a generation or a regeneration.

It ports the status and run parts of the web's [[app/frontend/components/admin/creator/BillCreatorLlmSummary.tsx#BillCreatorLlmSummary]] and the views under `llm-summary/` ([[bill-creator-summary-tab]]). The web files import Radix, Inertia and the page's type namespace, so the section copies their wording. It reads `bill` (with its `bill_llm_provisioning`, `bill_pipeline_refresh`, `bill_pipeline_last_failure`, `summary` and `summary_ai_unreviewed`) and `active_legislation_pipeline_run`, which the Summary tab's prop list gained for this section.

The section picks its view the way [[app/frontend/components/admin/creator/llm-summary/BillCreatorLlmSummaryStatus.tsx#BillCreatorLlmSummaryStatus]] does:

- A bill with no provisioning row says the pipeline has no data yet and offers Generate summary, which posts to `regenerate_summary` as the web's empty state does. A failed pipeline run adds the web's alert with the bill's external id and the run's reason, pointing to the Pipeline tab.
- A row that is completed or carries a draft summary shows the status badge, the Operator-pasted stamp for a pasted summary, and the published `bill.summary` as Markdown with the AI-unreviewed line when `summary_ai_unreviewed` is true. A draft that differs from the published text shows beneath it as Markdown, under the web's draft notice title. The view keeps the web's in-flight, unverified citation, failure and dropped-run notices, the breakdown toggle (or its "no section breakdown" line), and Regenerate summary.
- A generating row with no draft reads "Generating summary…" beside a disabled button. An abandoned one shows the web's notice instead and offers Generate summary.
- Any other row (queued, failed, dropped or never run) shows the badge, the failure reason or its fallback, the abandoned, queued and dropped notices, and Generate summary, labelled Retry after a failure. These buttons post to `generate_summary`.

The badge reads the web's words: Abandoned for a reclaimable queued or generating row, Ready, Failed, Queued…, Generating…, Skipped and Not generated. A stale row adds the web's "Summary is out of date" header with its change stamp and Regenerate from latest data. Every run button reads "Queueing…" while its request runs, and stays disabled while the bill's pipeline refresh is busy, under the web's pipeline-busy line. Regenerate also stays disabled while a run writes this row's summary or a clean-testimony run covers this bill, unless the row is abandoned.

Regenerate summary and Regenerate from latest data replace the draft, so each takes two taps through [[mobile/src/hooks/useTwoTapConfirm.ts#useTwoTapConfirm]], where the web opens a confirmation dialog. Generate summary and Retry take one tap, as on the web.

#### Generation options

The section ports the web's per-run model, reasoning level and instructions, and sends them with the same keys and the same omissions ([[bill-creator-summary-tab#Choosing the model for one regeneration]]).

It reads `summary_model_options`, `current_summarization_model` and `current_summarization_reasoning_effort`, already on the Summary tab's prop list. A row of buttons, one per offered model, stands in for the web's searchable combobox, and a second row offers Default, Low, Medium and High when the chosen model reasons. The picker opens on the standing model and its standing reasoning level, and reads "Standing default" when the server no longer offers the standing model. It sits wherever the web shows it: the empty state, the generate branch, an abandoned generating row and the completed view. A queued or running row disables it as the web does.

The request bodies follow the three web code paths:

- Generate summary and Retry post `summarization_model` when the choice is offered and `reasoning_effort` when one resolves, as [[app/frontend/components/admin/creator/BillCreatorLlmSummary.tsx#BillCreatorLlmSummary]] does. An admin who sets an inherited standing level back to Default sends `"default"`, so the run drops the standing level.
- Regenerate summary and Regenerate from latest data send the same two keys plus `summary_instructions`, trimmed of ASCII whitespace and left off when empty.
- The empty state's Generate summary sends the model and only a level the admin picked, never `"default"`, because the web's empty state passes the raw selection.

The web types instructions into its confirmation dialog. The phone's two-tap confirm has no dialog, so the field sits above the regenerate button, with the web's placeholder, help text, 2,000 code point counter, over-limit error and the "This run uses" line. Over the limit, the regenerate button stays disabled. A queued run clears the field, and a refusal keeps it, as the web keeps its retained instructions.

#### Answering generate and regenerate in JSON

[[app/controllers/bills_controller.rb#BillsController#generate_summary]] and [[app/controllers/bills_controller.rb#BillsController#regenerate_summary]] answer through `respond_after_write`, so the phone gets 200 with an empty body when the run is queued.

A refusal answers 422 with the reason under `details.generation`, the key the web reads from its Inertia errors, and the section shows that reason under the buttons. The reasons are the web's: no pipeline data, a model or reasoning level Sway does not offer, a generation already in progress, invalid instructions and a failed enqueue. A failed enqueue restores the row's retryable state ([[bill-creator-summary-tab#A failed enqueue leaves a retry path]]), so the same button works on the next tap. The web redirects exactly as before, with the same errors and the same regeneration notice.

A queued run refetches the tab. The row then reads queued, and polling takes over.

#### Polling while a summary is generated

The section refetches the tab every five seconds with [[mobile/src/hooks/admin/usePolling.ts#usePolling]] under the web's three conditions ([[bill-creator-summary-tab#Why the no-provisioning poll runs out]]).

The conditions are a queued or generating row, a busy pipeline refresh for this bill, and a bill with no provisioning row. The first two end on their own. The third is a standing fact about an unsummarised bill, so the phone bounds it as the web does: one minute per bill, twelve refetches. A different bill starts a fresh minute. A generation that finishes turns the poll off, because the row then reads completed or failed.

#### Preparing the summary prompt

The web's Prepare prompt asks for the optional `summary_prompt` prop by name with a partial reload. A JSON caller has no partial reload, so the phone asks with the query parameter `summary_prompt=1` on the Summary tab's address.

[[app/controllers/bills_controller.rb#BillsController#summary_prompt_prop]] builds the prompt for a mobile request only when that parameter is present, and the Summary tab's prop list names `summary_prompt` so the slice keeps it. The five-second poll never carries the parameter, so it never pays for the prompt ([[bill-summary-prompt-prop-delivery#Why JSON callers get it only on request]]).

The empty state's Prepare prompt button sends that request and shows the prompt as selectable text, under the web dialog's title and description. The prompt lives in the section's own state rather than in the tab data, so a poll that refetches the tab leaves it on screen. Like the web, the section records the pipeline refresh status the prompt was built against; once the bill's status moves on, it shows the web's "This prompt is out of date" notice and a Prepare again button. A failed request shows the web's error line.

#### What the phone leaves out

The section leaves out web pieces that belong to other sections, or that the phone has no way to show.

- The confirmation dialog itself, its warning about a pasted summary, and the per-bill memory of the chosen model and level across page loads. The choice lasts as long as the section stays mounted.
- The prompt view's Copy to clipboard button, which needs a clipboard module the app does not install. The prompt text is selectable instead.
- Editing and publishing the summary, Copy the draft into the box, news articles and categories, which later sections port.
- The busy overlay, the link to the failed run on the Pipeline tab, the pipeline status badge beside the busy line, the info popovers and the hover text on the stale stamp.

### The summary revisions section

The Summary tab lists every recorded revision of the bill's summary and restores one, as the web's revision history does ([[bill-creator-summary-tab#Planned recoverable summary history]]).

The web loads the list on demand through the optional `summary_revisions` prop, because a history of full Markdown bodies must not ride on the five-second poll. A JSON caller cannot name a prop, so [[app/controllers/bills_controller.rb#BillsController#summary_revisions_prop]] builds the list for a mobile request only when the address carries `summary_revisions=1`, as it does for the prompt ([[mobile-bill-creator#Sections#The summary generation section#Preparing the summary prompt]]). The tab's prop list names the key so the slice keeps it. A draft named by `draft_revision_id` arrives as `review_draft_revision`.

[[app/controllers/bills_controller.rb#BillsController#restore_summary_revision]] answers every branch through `respond_after_write` ([[surfaces#Dual-rendered JSON]]). A restore answers 200 with the new revision from [[app/serializers/bill_summary_revision_resource.rb#BillSummaryRevisionResource]]. The phone reads that revision's `publication_role` to learn whether a legacy revision came back as a draft. A summary that changed since the list loaded answers 422 with the web's alert as the message. The web keeps its redirects.

#### Listing and restoring revisions

[[mobile/src/components/admin/billCreator/SummaryRevisionsSection.tsx#SummaryRevisionsSection]] ports the web's [[app/frontend/components/admin/creator/llm-summary/BillSummaryRevisionHistory.tsx#BillSummaryRevisionHistory]]. The Summary tab renders it below the paste section.

A toggle opens the history and fetches the list the first time, with `summary_revisions=1` on the tab's address; Refresh history fetches again. The list lives in the section's state, so the five-second poll never carries it. Each row follows the web: the time, a Current badge when the revision's text equals the published summary, the role, the review state, "Evidence snapshot" or "Legacy (no snapshot)", the origin, and the provenance (the actor, else the provider and model, else an italic "Unknown provenance"). Inspect text shows one revision's raw Markdown in a preview pane under the list, which otherwise shows the published summary.

A published row offers Restore, disabled for the current text. A draft row offers Review draft instead. Restore opens a confirmation panel with the web's title, description, origin, provenance and review state. A revision with no evidence snapshot says it will become a review draft. Confirming posts `revision_id` and `expected_summary`, the published text the list was read against, to `restore_summary_revision`. A refusal keeps the panel open with the server's message, which is the web's alert when another operator changed the summary. A success refetches the tab and the list, and shows the web's notice.

The phone opens a draft by passing `draft_revision_id` to [[mobile/src/hooks/admin/useBillCreator.ts#useBillCreator]], which the screen holds as state. The server answers `review_draft_revision`, and the section shows the draft's text under the web's "Historical draft loaded for review" title until the admin closes it. A restore that comes back as a draft opens it the same way.

The phone leaves out the following web behaviours.

- The two-column layout and the list's scroll box: the phone stacks the list above the preview pane and lets the screen scroll.
- The dialog: the confirmation is a panel in the section, because a modal over a scrolling form adds nothing the panel lacks.
- Loading the draft into the editor: the web fills its summary editor with the draft. The phone shows the draft as selectable text; to publish it, the admin copies it into the Creator tab's summary field and declares its news usage there ([[mobile-bill-creator#Sections#The bill fields section#Declaring news evidence]]).
- Reset to published summary on the draft notice, which resets that editor.
- The history, chevron and rotate icons, and the spinner on Refresh history, which reads "Refreshing…".

### The summary sources section

The Summary tab lists what the model read for the bill's summary, as the web's ledger does ([[bill-creator-summary-tab#Why the panel lists what the model reads]]). The section is read-only.

[[mobile/src/components/admin/billCreator/SummarySourcesSection.tsx#SummarySourcesSection]] ports [[app/frontend/components/admin/creator/llm-summary/SummarySourcesLedger.tsx#SummarySourcesLedger]] and renders below the generation section. It reads `summary_sources`, which the tab's prop list already carried, and builds the web's four rows (bill details, bill text, law code and news) with the web's sentences, counts and stamps. A recorded run supplies the rows and the "Read by" line; with none recorded, the section shows the "Not recorded" notice and the rows describe what a run would read today. A row that differs from the recorded run gets "Changed since run", and a row built from today's facts gets "Newer than summary" or "Diff record newer" when its input postdates the summary. A bill the server sent no sources for shows an empty state, and an unsaved bill asks to be saved first.

Each row's View button shows the exact prompt section the model was given, in a panel under the row, as the web's modal does ([[bill-creator-summary-tab#Why each input opens a modal of its own]]). The text is large, so [[app/controllers/bills_controller.rb#BillsController#summary_source_documents_prop]] builds `summary_source_documents` for a mobile request only when the address carries `summary_source_documents=1`, as it does for the prompt ([[mobile-bill-creator#Sections#The summary generation section#Preparing the summary prompt]]). The tab's prop list names the key so the slice keeps it, and the five-second poll never sends the parameter. Every open asks again, and the panel says whether it is loading, could not load, was rebuilt just now, carried no such section, carried an empty one, or holds the text, which is selectable.

The phone leaves out the following web behaviours.

- The dialog: one panel at a time opens under its row, because a modal over a scrolling tab adds nothing the panel lacks.
- The info popover beside the heading and the Close button, which the second press on View replaces.
- The two-column row layout and the stamp badge styling: the phone stacks the name, sentence and stamps.

The web ledger has no write control. View only reads, so the section builds none.

### The news articles section

The Summary tab lists the news articles found for the bill, runs a newsroom discovery on request and reviews each article, as the web's news articles panel does ([[news-admin-ui#Explicit article retrieval]]).

[[mobile/src/components/admin/billCreator/NewsArticlesSection.tsx#NewsArticlesSection]] ports [[app/frontend/components/admin/creator/BillCreatorNewsArticles.tsx]] and renders last on the tab, as the web places the panel below the summary card. It reads `news_articles` and `receipt_status`, which the Summary tab's prop list already carried, so the section needs no fetch of its own.

Fetch articles posts to `/admin/bills/:bill_id/news_articles`. [[app/controllers/admin/bill_news_articles_controller.rb#Admin#BillNewsArticlesController]] answers any request that is not an Inertia request in JSON with `receipt_status` and `articles`. The section shows that answer until the tab data next reloads, and from then on the reloaded props, which name the same latest discovery. The button reads "Fetching articles..." while the request runs, and an unsaved bill disables it under "Save this bill to retrieve news articles."

The section keeps the web's notices for the receipt status (succeeded, no matches, unsupported and failed), its "No news articles retrieved yet" line when there are no articles and no status, and each article's row: outlet or "Unknown outlet", domain, the Direct coverage or Issue context stamp, Approved or Unapproved candidate, the title (a link only for an address [[mobile/src/utils/safeUrl.ts#isSafeCitationUrl]] accepts), byline and date, Text Available with Eligible for synthesis and the text origin, or the Link-only explanation, and a three-line excerpt.

#### Polling while a discovery runs

The section refetches the tab every five seconds with [[mobile/src/hooks/admin/usePolling.ts#usePolling]] while the receipt status reads queued or running, and stops once it settles.

The web polls the same way, and also while its own request runs. The phone's request answers with the receipt itself, so it skips that poll.

#### A refused discovery

A failed discovery answers 422 with `receipt_status`, `articles` and `error`, the receipt's failure reason, which the web reads from the Inertia error its redirect carries.

The section reads the receipt, its articles and the reason from the hook's `errorBody` ([[mobile-admin-area#Admin writes]]) and shows the web's failed alert with the reason in parentheses. A receipt that recorded no reason sends a null `error`, and the alert then has no parentheses. A request that fails with no such body (offline, a network error, a refusal from the admin guard) shows the same alert with the hook's message in parentheses, as the web shows its fallback.

The refused articles stay only until the tab data next reloads, as a successful answer does. A review reloads the tab, so the row then shows the reviewed article rather than the copy the refusal carried. The failed alert and its reason stay until the next fetch, as the web's do.

#### Reviewing an article

Each row of a saved bill ends with the web's review controls, and each control sends the web's PATCH body to `/admin/bills/:bill_id/news_articles/:id` ([[news-review#Review action protocol and format negotiation]]).

- Approve for this bill or Withdraw approval sends `approved` as the opposite of the article's state.
- The genre buttons (Reporting, Op-Ed, Editorial, Unknown) send `article_kind`; an article with no genre reads as Reporting.
- The stance buttons send `stance` as support, oppose, or an empty string for No stance.
- The Add text button, which reads Replace text for an article that has text, opens the manual text editor. Save article text sends the trimmed `text`; blank text shows "Article text cannot be blank." and sends nothing ([[news-review#Manual text enables synthesis without mandatory re-approval]]).

The genre and stance buttons stand in for the web's two dropdowns, and pressing the selected one sends nothing, as an unchanged dropdown fires no change. A row disables its controls while its own request runs, as the web disables only the busy article.

A successful review reloads the tab, as the web reloads `news_articles`, and a saved text also closes the editor. A refused review answers 422 with `{error: message}`; [[mobile/src/hooks/admin/useAdminMutation.ts#useAdminMutation]] reads that message and the row shows it under its controls. The web shows nothing for a refused review, because its panel reads the Inertia error only when it first mounts.

#### What the phone leaves out

The section leaves out two details of the web panel.

- The `readOnly` mode, which no web caller sets.
- The disabled review controls of an unsaved bill. Such a bill has no articles, so the phone renders no controls for it.

### The category override section

The Summary tab lets an admin set a bill's categories by hand, as the web's categories panel does ([[bill-categories-request-spec-design]]).

[[mobile/src/components/admin/billCreator/CategoryOverrideSection.tsx#CategoryOverrideSection]] ports [[app/frontend/components/admin/creator/BillCategoryOverride.tsx]] and renders last on the tab, below the news articles, as the web places it. Like the web, it renders only once the bill has a `bill_llm_provisioning` record, and it renders nothing for an unsaved bill.

Each assigned category is a chip with a remove button. Removing sends DELETE to `/bills/:bill_id/categories/:id` with no confirmation, as the web does, and a successful answer reloads the tab. Below the chips, every active category the bill lacks is a button; pressing one sends POST to `/bills/:bill_id/categories` with `category_id`, and a successful answer reloads the tab. With no chips the section says "No categories assigned yet. Add one below."

#### The category limit

The section counts only active chips against `max_active_categories_per_bill`. An inactive leftover shows as a removable chip but takes no place.

At the limit the buttons give way to "Maximum N categories assigned." A missing limit keeps the buttons, so the server's refusal names the real limit ([[bill-category-redirect-prop-freshness#Why the active-category counter only counts ACTIVE categories, and stays open when the limit prop is missing]]).

The buttons never list a category the bill already has, so the phone never sends a re-add. A direct caller that does gets a created answer and no change from the server ([[bill-categories-request-spec-design#Why re-adding an already-assigned category succeeds instead of erroring]]).

#### A refused category write

A refused add answers 422 with the server's message ([[bills-categories-controller-manual-assignment]]), and the section shows it under the buttons without reloading.

[[mobile/src/hooks/admin/useAdminMutation.ts#useAdminMutation]] reads the message, for example "Maximum 3 categories allowed per bill." A refused removal shows its message under its own chip.

#### What the phone leaves out

The section leaves out two details of the web panel.

- The success toasts "Category added" and "Category removed". The phone has no toast; the chip row changing on the reload is the confirmation.
- The dropdown and its remount after a failed add. Buttons hold no remembered value, so a refused add can be pressed again.

### The draft positions section

The Positions tab lists the organization positions a summary run drafted from testimony, and the admin approves, edits or rejects each one, as the web's draft cards do ([[bill-creator-positions-tab]]).

[[mobile/src/components/admin/billCreator/DraftPositionsSection.tsx#DraftPositionsSection]] ports the draft cards of [[app/frontend/components/admin/creator/llm-summary/LlmSummaryOrgPositions.tsx]] and [[app/frontend/components/admin/creator/BillCreatorOrgPositionCard.tsx#BillCreatorOrgPositionCard]]. The Positions tab renders it first, above the organizations section, as the web places the drafts above the arguments. A new bill shows "Save this bill to work through its testimony and organization positions." in place of both sections; the web names a picker above the tab, which the phone does not have.

The section reads `bill.bill_llm_provisioning` and lists every draft that is not marked rejected, keeping each draft's position in the stored list as its index. Each card is keyed on its `draft_token`, or on its name, stance and summary when the token is missing, with an occurrence count for duplicates, so a reload that drops one card leaves the others' typed edits in place ([[unique-stable-keys-react-list-identity#draftOrgPositionKeys]]).

A card shows the name, a stance stamp (Support, Oppose or Neutral, or the stored word itself when it is none of the three, or "No position" when blank), and the summary. A draft drawn from the news adds its quoted excerpt, the speaker and role, the source (pressable only for an address [[mobile/src/utils/safeUrl.ts#isSafeCitationUrl]] accepts, labelled by outlet, else title, else address) and the page, paragraph and character locator. A draft whose evidence was retracted shows the web's notice.

Approve, Reject and Edit follow the web card:

- Approve posts `org_name`, `support`, `summary`, `index`, and the draft's original `draft_org_name` and `draft_token` to `/bills/:id/approve_org_position`, then reloads the tab.
- Reject sends `PATCH /bill_draft_org_positions/:billId-:index` with `rejected: true` and the same original identity, then reloads the tab.
- The Edit button opens fields for the name, a Support, Oppose or Neutral choice and the summary. Apply edits changes the card only, and Approve carries the edits; Cancel edit discards them. No request leaves the phone until Approve, as on the web ([[org-position-card-editing-and-approval-ui#Why the inline editor keeps its own copy of the values]]).

Approve stays off while the draft's evidence is retracted, while a summary run or a clean-testimony run for this bill is in flight, and, for a draft not drawn from the news, while the bill has no testimony or testimony the run left out is unacknowledged. Reject and Edit stay on in every case except a request in progress. The section shows the web's three no-testimony sentences, "No draft positions generated." for an empty list with testimony on file, and the web's run-in-flight notice with its count of drafts held ([[bill-creator-positions-tab#Why Approve says on this tab why it is off]]). The clean-testimony check reads `active_legislation_pipeline_run`, which the Positions tab's prop list carries for this.

A refused approval or reject shows its reason on the card: `details.org_position` when present, else the server's message. A refusal flagged `private_individual_refusal` instead opens a panel on the card, "Approve anyway?", with the reason and the web's warning that approving publishes the name as a followable organization. Approve anyway resends with `override_private_individual: true`; Cancel closes the panel and leaves the reason on the card. A refusal that survives the override is shown, not offered again ([[private-individual-guard-override]]). The panel stands in for the web's confirmation dialog, as other sections on the phone use panels for dialogs.

#### Polling while a run is in flight

The section refetches the tab every five seconds with [[mobile/src/hooks/admin/usePolling.ts#usePolling]] while a summary run is queued or generating, or the bill's pipeline refresh is busy, as the web tab polls ([[bill-creator-positions-tab#What the positions tab polls for]]).

Both conditions end on their own, so the poll stops with them. A finished run reloads the drafts it wrote, and Approve comes back.

#### The organizations section on this tab

The Positions tab renders [[mobile-bill-creator#Sections#The organizations section]] below a "Supporting / opposing arguments" heading, keyed on the bill id and the sorted ids of the bill's organizations.

The section seeds its rows from `bill.organizations` once, at mount. An approval adds an organization to the bill, and without the key the reload would never reach the rows, so the new position would stay off the list. The key changes only when the set of organizations changes, so a poll that returns the same set keeps any summary typed and not yet saved ([[bill-creator-summary-tab#Why the organizations panel carries a remount key]]). Removing a published position uses that section's own Remove.

#### What the phone leaves out

The section ports the draft cards only; the rest of the web's testimony panel belongs to later sections.

- The testimony coverage notice with its acknowledgement, the supplemental testimony field, the positions error notice and the public testimony letters.
- The success toasts. The card leaving the list on the reload is the confirmation.
- The info popovers beside the heading, the stance stamp, Approve and Edit, and the stamp colours.
- The screen-reader link from a disabled Approve to the notice that explains it. The notices sit above the cards in reading order instead.
- The web's fallback text, "Approve failed." and "Reject failed.", used when the server names no reason. The phone shows the server's or the client's message instead, which always exists.

#### Answering approve and review in JSON

[[app/controllers/bills_controller.rb#BillsController#approve_org_position]] and [[app/controllers/bill_draft_org_positions_controller.rb#BillDraftOrgPositionsController#update]] answer every redirect branch through `respond_after_write` ([[surfaces#Dual-rendered JSON]]).

An approval, a reject and an edit answer 200 with an empty body, and so does a reject of a draft that is already gone. Every approval refusal answers 422 with the web's reason under `details.org_position`, the key the web reads from its Inertia errors, and the generic "Validation failed." as the message. A refusal for a person writing for themselves also carries `details.private_individual_refusal`, so the phone can offer the override the web offers ([[private-individual-guard-override]]). A reject or edit that names a draft the list no longer holds at that index answers 422 with the same list-changed reason under `org_position`. The update action's other refusals (a malformed id, no change named, an invalid stance, an over-long field, a missing identity) were already JSON, `{error, message}`, and the phone's client reads that message. The web keeps its redirects, flash notices and Inertia errors.

### The campaign drafts section

The Positions tab lists each campaign draft, a set of people who sent one letter template, and the admin approves, rejects or releases it, as the web's campaign card does ([[campaign-position-cards]]).

[[mobile/src/components/admin/billCreator/CampaignDraftsSection.tsx#CampaignDraftsSection]] ports [[app/frontend/components/admin/creator/BillCreatorCampaignPositionCard.tsx#BillCreatorCampaignPositionCard]] and its letter list. The tab renders it between the draft positions and the claimed affiliations, the web's order, keyed on the bill id. It reads `testimony_campaign_drafts` and `campaigns`, already in the Positions tab's prop list, and draws nothing when there are no drafts. Each card is keyed on the draft's `content_hash` and finds its approved campaign through `source_campaign_draft_hash`.

A card shows the name line, the APPROVED and CAMPAIGN stamps, the evidence line ("3 senders · 2 letters · sent through <domain>") and the web's note that approving never creates an organization. An unnamed campaign reads "3 people sent this letter". A name over 120 characters shows one line with a "Show full name" toggle. The name, position and summary start from the approved campaign, or empty and Support for a new one, and a reload takes the server's values unless the editor is open.

The buttons follow the web card:

- The Edit button opens fields for the name, a Support, Oppose or Neutral choice and the summary; Cancel closes them and keeps what was typed.
- Approve as this campaign, or Update this campaign once approved, posts `name`, `support`, `summary` and `content_hash` to `/bills/:id/campaigns`. It stays off while the summary is blank, the bill has no testimony, a summary run or a clean-testimony run is in flight, or left-out testimony is unacknowledged: the claimed affiliation card's checks ([[mobile-bill-creator#Sections#The claimed affiliations section]]).
- Reject and, before approval, Mark as Individual Letters post `content_hash` to `reject_draft` and `mark_individual_draft`.
- A rejected draft, or one marked individual and not approved, collapses to a stamped row (REJECTED or INDIVIDUAL LETTERS) whose Restore posts to `restore_draft`.

Every write reloads the tab on success and shows the server's notice on the card. A refusal shows `details.campaign_position`, else the server's message.

An approved card will carry the organization link below the note, where the web places it.

The letters open under "Show 2 letters". The first open on any card fetches every draft's letters once ([[mobile-bill-creator#Sections#The campaign drafts section#Serving the letter text to the phone]]) and keeps them in the section, so every other card opens without a request and the poll never carries them ([[campaign-letter-disclosure#Why the list asks for its own letters]]). The list shows one letter at a time with Previous, Next and "1 of 2", each with its number, sender (address, else domain, else "Unknown sender"), a DUPLICATE stamp for a repeat and the selectable text. It says when the letters are loading, could not be loaded (with Try again), or could not be produced. A draft whose `letter_count` is zero offers no letters ([[campaign-letter-disclosure#Why the disclosure is gated on the count rather than the letters]]).

#### Serving the letter text to the phone

The phone reads a campaign's member letters only on the Positions tab, and only when its address carries `testimony_campaign_letters=1`.

The letters are a draft's whole testimony text, so they must never ride the tab's five-second poll ([[campaign-letter-disclosure#Why the letter text is a prop of its own]]). A JSON caller cannot name a prop, so [[app/controllers/bills_controller.rb#BillsController#testimony_campaign_letters_prop]] builds the bundles for a mobile request only when the parameter is present, as it does for the revision list ([[mobile-bill-creator#Sections#The summary revisions section]]). The parameter reaches no other tab, because the tab's prop list slices the answer and only the Positions list names the key. The bill creator is admin-gated, and the public bill page builds no creator props, so `GET /bills/:id` never carries the text.

#### Answering campaign writes in JSON

[[app/controllers/campaigns_controller.rb#CampaignsController]] answers the approve, reject, restore and mark-as-individual writes through `respond_after_write` ([[surfaces#Dual-rendered JSON]]).

Each write answers 200 with `notice`, the sentence the web puts in its flash. The phone shows it on the card, because the approval notice is the only place an admin learns that the approval replaced an earlier decision for the same campaign name ([[campaign-letter-disclosure#Why replacing an earlier decision is reported as success]]). Every refusal answers 422 with the web's reason under `details.campaign_position`, the key the web reads from its Inertia errors, and the generic "Validation failed." as the message. The web keeps its redirects, flash notices and Inertia errors. Linking a campaign to an organization keeps its redirects for now.

#### What the phone leaves out

The card keeps the web card's rules and drops its chrome.

- Linking an approved campaign to an organization, which a later section adds.
- The info popovers beside the CAMPAIGN stamp, the evidence line and the letters toggle, and the stamp colours.
- The numbered page buttons: Previous and Next replace them, and the letter list shows its page count once rather than above and below.
- The screen-reader link from a disabled Approve to the notice that explains it. The draft section's notices sit above the cards.
- The web's "Approve failed.", "Reject failed.", "Restore failed." and "Mark individual failed." fallbacks. The phone shows the server's or the client's message, which always exists.
- A failed letter fetch is remembered for the section, not per card, so Try again on any card retries for all.

### The claimed affiliations section

The Positions tab lists each position a letter's sender claimed on behalf of an organization, and the admin approves it or drops it, as the web's claimed-affiliation card does ([[campaign-position-cards#Claimed affiliation card shape and partial-evidence rule]]).

[[mobile/src/components/admin/billCreator/ClaimedAffiliationsSection.tsx#ClaimedAffiliationsSection]] ports [[app/frontend/components/admin/creator/BillCreatorClaimedAffiliationCard.tsx#BillCreatorClaimedAffiliationCard]]. The tab renders it between the draft positions and the organizations, keyed on the bill id, and the section draws nothing when `testimony_claimed_affiliations` is empty. That key is already in the Positions tab's prop list, so no server change was needed. Each card is keyed on the claim's `position`, and a claim with no phrase, role or sender draws no card.

A card shows "Maybe: <name>", the stamp "CLAIMED, NOT VERIFIED", the evidence under "Why this organization" and the web's caution that nothing has confirmed the claim. The evidence lists the phrase, the role claimed and the sender, each only when present. A phrase longer than 160 characters shows two lines with a "Show the whole phrase" toggle. The name starts as the claim's `org_name`, or empty when the claim names none, the position as Support, and the summary as empty ([[campaign-position-cards#Why the affiliation card seeds from the organization name]]).

Approve, Reject and Edit follow the web card:

- The Edit button opens fields for the name, a Support, Oppose or Neutral choice and the summary, and pressing it again closes them. Cancel closes them too and keeps what was typed.
- Approve posts `org_name`, `support`, `summary` and `claimed_affiliation_position` to `/bills/:id/approve_org_position`, then reloads the tab. It stays off while the summary is blank, the bill has no testimony, a summary run or a clean-testimony run is in flight, or testimony the run left out is unacknowledged. The summary and run checks are the draft cards' checks ([[mobile-bill-creator#Sections#The draft positions section]]).
- Reject hides the card until the tab remounts and sends nothing, as on the web. The claim stays in the list the server sends.

A refused approval shows its reason on the card, `details.org_position` first, else the server's message. A refusal flagged `private_individual_refusal` opens the "Approve anyway?" panel instead, and Approve anyway resends with `override_private_individual: true`. A refusal that survives the override is shown, not offered again ([[private-individual-guard-override]]). The panel stands in for the web's confirmation dialog.

#### What the phone leaves out

The card keeps the web card's rules and drops its chrome.

- The info popover beside "Why this organization" and the stance badge colours.
- The screen-reader link from a disabled Approve to the notice that explains it. A blank summary shows "No summary yet" beside Approve, and the draft section's notices sit above the cards.
- The web's "Approve failed." fallback. The phone shows the server's or the client's message, which always exists.
