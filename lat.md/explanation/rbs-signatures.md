---
lat:
  mode: explanation
---

# RBS signatures

Sway's Ruby types live in three places — generated signatures, hand-written ones for the app, and shims for libraries. Signatures collide in two ways, and both are expensive because the gate that would name them plainly is the one nobody runs.

## Why a spec's helpers are invisible to Steep

`let(:thing)` and `def thing` inside a `describe` block define a method on an example-group class RSpec builds at runtime. Nothing about that class exists in the source Steep reads, so a call to `thing` reports `Ruby::NoMethod`.

The alternative — teaching Steep to model RSpec's DSL — would mean tracking a nesting of anonymous classes through blocks that are `instance_eval`'d. `sig-test/` takes the cheaper route and states the helpers directly.

## Why a typed spec double is a plain class rather than a Struct

A method written inside a `Struct.new(...) do ... end` block is attributed by Steep to the class enclosing the block, not to the anonymous Struct subclass, so a call to it on the double reports the method as missing.

`EnvCredentialScanner::Read`, `SubprocessSpecHelpers::UnreapableWaiter` and the `SettingsWrite` record in `spec/lib/sway/settings_spec.rb` are therefore ordinary classes — `attr_reader` plus a hand-written `initialize` — even where a `Struct.new` would be the shorter way to write the same thing, and `sig-test/` declares each one as the plain class it is. `Class.new(SomeBase) do ... end` fails the same way from the other side: the block's `self` is typed as bare `::Class`, so a class-body DSL call inside it does not resolve, where a named class with an ordinary body resolves exactly as a production class does. A named top-level class also sits outside any `describe` or `it` block, so RuboCop's `Lint/ConstantDefinitionInBlock` never applies.

## Why the declarations land on ::Object

Steep resolves a `describe` block's body against whatever `self` is declared to be, which `sig-test/rspec_dsl.rbs` leaves as the top-level object. A helper on `::Object` is therefore in scope in every block, in every spec.

It is also what makes it dangerous. A helper written for one spec is not scoped to that spec: it is a method on every object in the type universe, including the one the next spec's helper of the same name wants to be.

## Why a repeated name stops the whole check

Two declarations of one name with different types is a duplicate definition on `::Object`, and the two type gates disagree about how bad that is.

`bundle exec rbs -I sig -I sig-test validate` refuses the whole tree and names the file it noticed second. `bin/steep check` is worse, because it does not refuse: it picks one of the two definitions and then reports a type error at every call site expecting the other. The error count bears no relation to the size of the mistake.

A single `def destination: () -> String` added to `sig-test/object_spec_methods.rbs`, colliding with one already declared elsewhere in `sig-test/`, can produce thousands of error lines, nearly all of them from that one line, on a run that was clean before it.

The defence is that a name is checked across the whole `sig-test/` tree before it is declared, and that generic words are avoided as helper names. `report`, `service`, `result`, `settings` and `destination` are the shapes that collide; `backup_report` and `recurring_yml` are the same helpers named so they cannot.

## Why some specs get their own file

`sig-test/object_spec_methods.rbs` is the shared file, edited by whoever is working on any spec at all. A declaration sitting in it went stale the moment that spec's signature changed, and nobody reading the spec looked there.

A per-spec file at the spec's own path — `sig-test/requests/bills_spec.rbs` for `spec/requests/bills_spec.rb` — keeps the declaration somewhere its author will find it again. The shared file remains for helpers that genuinely are shared, such as factory attributes.

## Why a spec ivar name cannot be one an app class uses

An instance variable read inside an RSpec block resolves on `::Object` as well, and that namespace reaches further than the helper one: rbs refuses a name whose type differs from the same name on any class it can see.

`@user` is the clearest case. Six hand-written signatures already declare it — `User` in `sig/services/influence_service.rbs`, `User?` in `sig/services/score_updater_service.rbs`, `untyped` in `sig/services/sway_registration_service.rbs` — so a seventh declaration on `::Object` for whichever account a system spec signs in as answers `RBS::InstanceVariableTypeError` rather than being scoped to specs. Real Steep reports the same conflict, including the case where the competing declaration is only implied by an `attr_reader`.

The resolution is on the spec side, because the app's names are the ones with callers. The fixtures were renamed to words no app class claims — `@signed_in_user`, `@bill_of_the_month`, `@licenses_dir`, `@atomic_write_dir`, `@congress_locale` — each checked against `sig/`, `sig-test/`, the rbs collection and rbs's own core and stdlib before being declared once in `sig-test/spec_instance_variables.rbs`. An ivar belonging to a spec-defined module or class is not in this namespace at all and stays in that spec's own file under `sig-test/`.

## Why the mock DSL is declared with typed targets

`expect(x).to receive(:y)` is four calls, and leaving any of them `untyped` costs the block parameters of the fifth.

`sig-test/rspec_dsl.rbs` therefore returns real classes from `expect`, `allow`, `allow_any_instance_of` and `expect_any_instance_of`, and gives `receive` a matcher class whose customisation methods each return `self`, so a chain of them stays typed to its end.

The block types on those declarations are `{ (*untyped args, **untyped kwargs) -> untyped }` rather than the positional-only form. A block naming a keyword parameter — `have_received(:submit) { |items:| … }` — binds nothing against a positional-only block type, and the parameter then reads as `untyped` everywhere it is used. `ActiveSupport::Notifications.subscribe` needed the same treatment for the opposite reason: `sig-test/active_support_notifications.rbs` states the five parameters the instrumentation API yields, so a query-plan helper's `payload` is a `Hash` rather than a `nil` the checker refuses to index.

## Why a shim stops being a shim when the collection grows

The second collision is quieter. A library with no published types gets a hand-written shim under `sig/shims/`. Each of those files was written against a true statement about the library's packaging at the time.

That statement expires. `rbs collection install` runs on every verification pass, and gems ship their own signatures on their own schedule, so a shim becomes a duplicate of an upstream declaration with no edit to the shim and nothing in the diff to notice. Shims have turned over that way — Octokit, Geocoder, `sentry-ruby`, `anyway_config`, `ActionController::Parameters#transform_keys` and `String#starts_with?` — each carrying a header comment asserting the library published nothing.

The library's own signature is usually the better one to keep: it is maintained by people who know the library and it covers the whole surface rather than the part Sway happened to need. Four of the six were adopted on that basis; Geocoder and `ActionController::Parameters#transform_keys` were not, for the reason the next section gives. What survives in a shim is the part upstream still does not say — `anyway_config`'s private callbacks, the `Anthropic::Errors` hierarchy — and a header comment naming a library as unpublished is a claim with a shelf life.

## Why a hand-written signature can outrank the standard library's

The rule that upstream signatures win has an inverse. A shim is sometimes kept because the published signature is narrower than the language itself, and adopting it would reject working code.

`Open3` is that case. RBS's own `core/io.rbs` describes `IO#external_encoding` in prose and never declares it, and `stdlib/open3` declares `popen3` as taking `(*String, ...)` — modelling neither the `[executable, argv0]` pair that Ruby's spawn family accepts in place of an argv string, nor `capture3`'s leading environment hash, nor its `chdir:` keyword.

Sway depends on all three. `Sway::Subprocess.argv` rewrites a lone command into `[[binary, binary]]` so a hung child carries a recognisable argv0; `spec/config/uncommitted_digest_spec.rb` passes `chdir:` to `capture3` about fifteen times; `spec/config/kamal_vault_account_spec.rb` passes an environment hash first. Declaring `library "open3"` would have swapped a signature that admits these for one that does not, and turned each site into a reported call-site bug.

`ActionController::Parameters#transform_keys` is the same case with a worse ending. The generated actionpack signature declares it as `() { () -> untyped } -> untyped` — a block taking no arguments — while the real method yields the key, as `transform_values` two lines above it in the same generated file is correctly declared to do. `BillsController#bill_params` passes `&:underscore`, so the call reports a block-type mismatch.

Here the shim cannot be restored. Unlike Geocoder, actionpack cannot be marked `ignore` in `rbs_collection.yaml` without giving up signatures for the whole framework, and a shim alongside the generated file is a duplicate definition, which stops `rbs validate` outright. A warning at one call site is the cheaper of the two, so the shim stays deleted and the warning stands as a known upstream defect.

The distinction is which direction the two signatures differ in. Upstream wins where it is the more complete description of the library, which is the ordinary case. The shim wins where upstream is an incomplete description of Ruby, and the gap is one the code stands in.


## Why RBS names the canonical model constants

The model constants [[app/models/organization_notification_delivery.rb#OrganizationNotificationDelivery]] and [[app/models/pending_organization_digest_entry.rb#PendingOrganizationDigestEntry]] match their persisted table names. Their signatures and callers use those canonical constants directly.

Each model has one class declaration in RBS. That keeps the runtime class and its signature aligned without compatibility constants that would create a second type name for the same class.

## Why global spec helper names have unique signatures

Steep places methods defined in RSpec example-group blocks on `Object`, so their signatures share one namespace. The helper in [[spec/models/pending_organization_digest_entry_spec.rb]] therefore uses a distinct name from the helper in [[spec/models/pipeline_activity_log_entry_spec.rb]], whose keyword-only contract is declared in [[sig-test/object_spec_methods.rbs]].

## Why a serialized column's generated signature is wrong

`rbs_rails` generates a model's attribute signatures from the database column, which is the wrong type whenever the model runs the value through a serializer on the way in and out.

`LegislationPipelineRun` stores `stages` in a `text` column and declares `serialize :stages, coder: JSON`, so the generated `stages` reads `String?` while every caller — the pipeline job, `LegislationPipelineRunService`, the factory — treats it as an array of stage keys. Nothing in `app/` ever reads or assigns a bare String there.

The correction goes in the hand-written `sig/models/legislation_pipeline_run.rbs`, not the generated file, which is rewritten on demand. A declaration in the class body overrides one from the generated `GeneratedAttributeMethods` module without becoming a duplicate definition, which is what makes this legal where a second plain declaration of the same name would stop `rbs validate` outright. `parent_run_id` uses the same shape.

One wrong attribute type spreads: `stages` alone accounted for five errors in the pipeline job and two in the run service, none of which were call-site bugs.

## Why a declaration sometimes belongs on the Relation

A scope that chains another scope is type-checked with `self` as a Relation, not as the model class, so the chained name has to be declared on the Relation even though the model already declares it.

`LegislationPipelineRun.abandoned_candidates` calls `awaiting_live_summary_batch` from inside its own scope body. Rails resolves that at runtime through `Relation#method_missing`, which delegates back to the class; Steep has no such fallback, so `ActiveRecord_Relation` carries its own declaration of the chained scope.

The association proxy has the same shape for a different reason. `each_pipeline_run_bill` walks bills with a stable cursor rather than an `.order` scope, and the vendored `activerecord.rbs` overloads for `find_each` predate Rails' `cursor:` and `order:` keywords — so the proxy gets a declaration that admits them rather than the call being left untyped.

## Why a concern that calls super declares its host

A module's `super` has no target of its own: the method it overrides lives on whichever class includes it. Steep resolves `super` inside a module against the module's declared self-type, so a concern without one reads as `Ruby::UnexpectedSuper`.

`BillCreatorRunPinRedirects#_compute_redirect_to_location` is that case. It wraps the redirect-target hook Rails declares in `ActionController::Redirecting`, which `ActionController::Base` mixes in, and `ApplicationController` is the class that includes the concern.

The narrower constraint, `: ActionController::Redirecting`, clears the diagnostic on its own, and it is still an incomplete description of the host. The body also reads `request`, declared on `ActionController::Metal`, which `Redirecting` never reaches. That read goes unreported in a bare module only because `sig/shims/object_fallback.rbs` gives every Object a `method_missing` answering `untyped`; with that shim absent, Steep reports `Ruby::NoMethod` for `request` at each of its two reads. `: ActionController::Base` names the host the concern actually has, covers both members, and is the constraint `JsonErrorRenderable`, `RateLimitResponder` and `AdminOnlyDirectUploads` already declare for the same reason.

`rbs validate` checks the constraint where the module is included, so a class that is not an `ActionController::Base` is reported at its `include`, not at the `super`.

`url_from` stays declared inside the module. No vendored signature carries it, so no self-type can supply it.

## Why the state_machines DSL is declared on Class

`state_machines-activerecord` ships no RBS and has none in the collection, so its DSL is declared in `sig/shims/external_auth_libs.rbs` by reopening `Class` — the methods are called in a model's class body, which is where that puts them.

The shim predates this and was incomplete rather than absent, which is what made completing it the cheaper option than declining to type the DSL at all. It declared `state_machine`, `event`, `transition` and `after_transition`, but not `before_transition` or `any`, so those two read as missing methods on the model's singleton.

Its block types were also actively wrong rather than merely loose. The yielded record was declared `ApplicationRecord`, so every callback that touched a column belonging to the actual model failed — `run.current_stage=` on a `LegislationPipelineRun` among them — and passing that record to anything expecting the concrete model failed too. The record is now `untyped`, because the DSL yields whichever model declared it and `Class` has no type variable to carry that. The second parameter was `top?`, which has no methods at all; it is now a declared `StateMachines::Transition` carrying the `from`, `to` and `event` readers the callbacks actually read.

Completing it also retired two `steep:ignore` blocks in `PipelineRunBill`, whose own comments named the shim's `any =>` gap as their reason. Steep reports a redundant ignore, so the blocks were removed and the code inside them is checked rather than skipped.

The DSL methods take `(*untyped)` and declare no keyword rest. `transition PHASE_52_NON_TERMINAL_STATES => :cancelled` and `before_transition any => any` both pass a hash whose keys are not Symbols, and RBS keyword-rest parameters can only carry Symbol keys — so a `**kwargs` declaration rejects the very calls the DSL is built from, while positional packing accepts both those and the ordinary `transition queued: :running` form.

Six models use this DSL. Declaring it once on `Class` is what the shim already chose, and the alternative considered here — declaring the DSL methods on the model itself — was rejected as false: `before_transition` lives on the gem's machine object, not on the model, so a model-level declaration would type-check a call that raises at runtime.

## Why a mailer's class-level call needs its own declaration

`SomeMailer.some_action(...)` is generated by Rails at runtime, so no signature exists for it anywhere and every action a caller invokes has to be declared on its own mailer.

The return type is `ActionMailer::MessageDelivery`, not the mail itself. That object is a lazy proxy: `deliver_now` and `deliver_later` are its own methods, and everything else a caller reads — `subject`, `body`, `to`, `from`, `text_part` — forwards to the underlying `Mail::Message` through `method_missing`. Declaring that forwarding once on `MessageDelivery` is what lets a `SomeMailer.action(...).body` chain check without hand-listing every forwarded reader, and it is a description of the real object rather than a concession.

`ActionMailer::Base.default` is a separate case. The vendored signature declares only the setter shape used inside a class body, `default from: "..."`, returning void; the real method also answers as a getter and returns the merged `default_params` hash, which is the form a spec reads.

## Why a growing hash literal needs an inline annotation

Steep infers a bare hash literal as a record (shape) type, one entry per key it saw at that line. Adding a key afterwards checks the new value against that narrow shape, not the wider type the hash is heading towards.

For example: `{from: "x", to: "y", run_id: 1}`, followed later by `payload[:auto_included] = true`.

`PipelineActivityLogger.emit_state_transition!` builds `payload` this way and then conditionally adds `:auto_included`, `:stage`, `:reason` and `:bill_external_ids` — a bool, and values read out of `Pipeline::Current.current_auto_include_context`, an already-`untyped`-valued hash (see its own `sig/models/pipeline/current.rbs` header). The eventual consumer, `emit!`, already declares `payload: Hash[Symbol, untyped]` — the payload is genuinely polymorphic by event type, the same reasoning `serialize_entry`'s return type documents in `sig/services/pipeline_activity_logger.rbs`. An inline `#: Hash[Symbol, untyped]` annotation on the literal's assignment line tells Steep to type it that way from the start, matching what the rest of the file already treats this shape as, rather than the accidental narrower record type of whichever keys happened to be in the first assignment.

## Why an ensure clause reads a local Steep cannot type

A block written `do … ensure … end` gives Steep nothing to read: the local the ensure clause needs was bound inside the body it protects, so every read there reports `Ruby::FallbackAny`.

The shape that types is an explicit `begin … ensure … end` with the reads standing above it. An `around` hook that captures three Capybara settings, overwrites them, runs the example and restores them becomes the three captures, then `begin`, then the mutations and `example.run`, then `ensure` and the restores. Captures are pure reads, so hoisting them changes nothing at runtime, and the ensure clause now reads locals assigned on a path that cannot have been skipped.

This was the largest single source of hint-level diagnostics in the tree — 56 system specs carry that same Capybara hook, and most service and request specs carry a smaller version of it.

Where the value is a resource the body acquires rather than a setting it overwrites — `Dir.mktmpdir`, `Tempfile.new`, `IO.pipe` — the acquisition sits immediately above `begin` in the same idiom, and the `if tmp_dir` test that used to guard the ensure clause goes with it, being dead once the local is assigned before the region rather than inside it. A block form that owns the cleanup itself, `Tempfile.create`, is better still: it deletes the `ensure` clause rather than making one typeable.

The shape that fails is the one that looks like it ought to work — a nilable local seeded above `begin` with an inline `#: T?` annotation, acquired inside it, read through `&.` in the ensure clause. steep-rs forgets any local whose type the body changed, and a narrowing from `T?` to `T` counts as a change, so every read of it there reports `Ruby::FallbackAny`. Steep 2.1.0 settles the union of the entry and body types instead and reads it cleanly. The two checkers disagree on exactly that case; hoisting the acquisition sidesteps the disagreement, because a local whose type never changes is one there is nothing to forget.

## Why a provably-safe value still needs a guard

Several core-library return types stay nilable in RBS even at a call site that has already ruled nil out — the signature describes the method in general, not what that call site already proved.

This shows up in `String#[]`, `MatchData#begin`/`#end`, `Regexp.last_match`, the elements a fixed-size `String#split` destructures into, `String#scan`'s element type for a capture-less `Regexp`, and `String#index`.

Each site below proved nil impossible, and the signature still cannot say so.

- `Testimony::LetterSplitter#call` slices `@text[start...finish]` where both offsets were derived from `@text` itself, so the slice cannot fall outside the string. `String#[]`'s range overload returns `String?` unconditionally.
- `#marker_starts` reads `Regexp.last_match` inside the block passed to `@text.scan`, where a match is always current. The method's return type carries `MatchData?` everywhere it is called.
- `GenerateDiffsService::ApplyOperations` splits on `" -> "` only after confirming the separator is present, so the split returns two elements — but Ruby's multiple assignment reads each through `Array#[]`, whose per-index type is `String?`.
- `Testimony::ClassificationPromptBuilder.version_digest` takes the first 12 characters of a SHA-256 hex digest, always 64 long. `String#[]`'s two-Integer overload still returns `String?`.
- `Testimony::SourceKindRules#person_speaking_for_org_evidence` reads `role_match.end(0)` after confirming the match. Group 0 is always present, but `MatchData#end` shares its signature with numbered groups, some genuinely optional.
- `Testimony::CharacterRepair`'s `SEED_VOCABULARY` scans with a capture-less `CLEAN_WORD_RUN`, so every element is a `String`. `String#scan(Regexp)` cannot distinguish that from a capturing pattern and stays `Array[String | Array[String?]]`. This one carries an inline `#: Set[String]` assertion rather than a guard, because every guard shape that narrows the elements is one rubocop rejects — `Style/MapCompactWithConditionalBlock` on the `filter_map` form, and the `select` it suggests instead narrows nothing.
- `spec/services/testimony/source_kind_classifier_spec.rb` builds offsets with `full_text.index(texts[n])`, always a hit because the needle built the haystack. `String#index` still returns `Integer?`.

Each of these keeps the invariant visible as a guard — `nil` fails the operation the same way an unmatched case already does, or a spec's `|| raise` names the fixture assumption it depends on — rather than reaching for `.to_s`, which would silently fold a real future break in the invariant into an empty string or a zero offset instead of surfacing it.

## Why a guard against an impossible shape means the type is wrong

A runtime guard that Steep reports as `Ruby::UnreachableBranch` is usually not dead code. It is the signature above it promising a shape the value does not carry, and the correction belongs in the type rather than in the guard.

It is the inverse of the case where a provably-safe value still needs a guard. There the type was too loose for a value the code had already proved safe; here it is too tight for a value nothing has proved at all. Two places in `app/` sit on that side, and both keep the guard.

`PipelineActivityLogEntry#inspect_query` reads `payload`, a `text` column deserialized by `serialize :payload, coder: JSON`. The coder answers whatever the stored document parses to, which is not constrained to an object, and `PipelineActivityLogger.serialize_entry` tests the same value twice before it trusts it. The reader nonetheless stays `Hash[String, untyped]`, because its callers index it directly: declaring it `Hash[String, untyped] | String | nil` answers fresh `Ruby::UnresolvedOverloading` errors across several specs, none of them a real bug. The untrust is bound to a single local instead — `raw_payload = payload #: untyped` — so it stays inside the one method that does not trust the column, and the reader keeps the type its callers depend on.

[[app/services/bill_news_article_fetch_service.rb#BillNewsArticleFetchService#process_candidate]] is the other half of the pattern, the one where the signature rather than the call site was wrong. Its argument is a candidate from [[app/services/brave_search/client.rb#Client#search]], and the external API response behind that client is an external boundary whose elements the service did not produce. `spec/services/bill_news_article_fetch_service_spec.rb` holds the service to checking rather than assuming, verifying that malformed candidates are safely rejected. The parameter reads `untyped` in `sig/services/bill_news_article_fetch_service.rbs` for that reason, which also keeps the `candidate.is_a?(Hash)` guard reachable — the upstream candidate answer, guarded per element.

Neither site reaches for `steep:ignore`. An ignore comment hides the diagnostic and leaves the signature still saying something false to the next reader, where naming the untrust at the boundary it starts from leaves the type honest and the guard checked.

## Why Diff::LCS needs a project shim for sdiff

The vendored `diff-lcs` signature declares only `LCS`, `diff`, and `patch!` — never `sdiff` or the `ContextChange` result it yields — so `Diff::LCS.sdiff` reads as undefined even though it is real, shipped API.

This is the missing-signature case, not the outranking case `Open3` demonstrates above: nothing about `sdiff` conflicts with what `.gem_rbs_collection/diff-lcs/1.5/diff-lcs.rbs` already says, that file is simply incomplete. `sig/shims/diff_lcs.rbs` adds the method and the two-sided `ContextChange` reader surface `GenerateDiffsService::DiffRenderer#make_diff_block` reads (`#action`, `#old_element`, `#new_element`), following the same pattern as `sig/shims/rubygems_specification.rbs`.

## Why a mixed-value document Hash needs a per-key guard

`GenerateDiffsService`'s payload Hash types every key with one shared value union, since different keys hold a `String`, an `Array`, or a `Hash[String, Integer]`. Reading one key back gives the whole union, not that key's own narrower type.

`stats["sections_modified"]` on `@diff_result["stats"]` fails because `nil` and `Array` are members of the `diff_result_value` union too, even though this particular key is always the stats `Hash`. `GenerateDiffsService::MarkdownRenderer#render` narrows with `stats.is_a?(Hash)` rather than casting, so a payload that someday failed to carry a stats `Hash` renders without the two stat lines instead of raising — consistent with the rest of the class treating a malformed payload as something to render around, not fail on.

## Why the lint tooling is left out of the check

The custom RuboCop cops and the specs that exercise them are excluded from both type-check targets rather than given signatures.

Two things make them a bad fit. The linter publishes no signatures of its own,
so nothing the cops or their harness call has a declared type; and the cops are
metaprogramming — the node-search helper generates predicate methods at load
time, so the methods a cop calls on itself do not exist in its source at all.
A signature for either would be a hand-written description of a library Sway
does not own.

The cost of excluding them is small, and that is the deciding half. They are
lint tooling rather than application code: nothing a reader sees depends on
them, and their own specs run the linter's offence harness against fixtures, so
a mistake in one shows up as a red lint spec rather than as a wrong answer on a
page.

## Why this is not caught by the verification gate

`scripts/dip/verify.sh`'s `rbs-validate` lane ran `bundle exec rbs validate` with no `-I` flags. That command loads no project signatures, prints nothing and exits 0, so the lane never looked at `sig/` or `sig-test/` at all.

Both collisions were therefore only visible through `bin/steep check`, where they arrive disguised as call-site errors far from their cause. The lane passes `-I sig -I sig-test`, which is what makes it name a duplicate directly, in one line, at the file that introduced it.

## Redirect helpers preserve request arguments

Rails follow_redirect! accepts a headers hash and forwards other request keywords to the redirected request. Both spec-helper declarations preserve that contract and return the resulting integer HTTP status.

The redirect helper supplies a Referer unless the caller supplied one. Inertia request specs need their version and request headers on the destination request; a zero-argument signature incorrectly rejects that supported flow. RBS parsing checks syntax, while the full validation and Steep lanes check compatibility.
