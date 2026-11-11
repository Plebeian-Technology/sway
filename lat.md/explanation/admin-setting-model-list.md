---
lat:
  mode: explanation
---

# Why the AdminSetting model list changes the way it does

Why AdminSetting::SUPPORTED_MODELS provides a twelve-model baseline, how dynamic offered models are managed via OpenRouter, and why inclusion validations check only the column that changed.

## The twelve-model baseline

AdminSetting::SUPPORTED_MODELS provides a frozen twelve-model baseline spanning direct Claude models, OpenRouter Latest selections, and OpenRouter Auto.

The baseline establishes three direct Claude tiers (`claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`), eight OpenRouter Latest models (`Opus Latest`, `Sonnet Latest`, `Haiku Latest`, `Gemini Argon Latest`, `Gemini Flash Latest`, `GLM Latest`, `Deepseek Pro Latest`, `Deepseek Flash Latest`), and `OpenRouter Auto`. `AdminSetting::SUPPORTED_MODEL_LABELS` provides curated human-readable titles for each entry.

## Dynamic offered models and OpenRouter catalog

The offered_models JSON column lets administrators customize available models without deployments by adding structured-output models from OpenRouter.

When `offered_models` is nil or empty, `AdminSetting.offered_models` defaults to `SUPPORTED_MODELS.dup`. When populated, `AdminSetting#add_offered_model!` verifies candidate model IDs against `SUPPORTED_MODELS` or `Llm::OpenRouterModelsService.lookup`, ensuring only verified structured-output models are persisted. `AdminSetting.offered_model_labels` merges labels from `Llm::OpenRouterModelsService.call` with curated `SUPPORTED_MODEL_LABELS` so every offered model has a readable title.

## Specialized decision and extraction models

AdminSetting persists dedicated decision_model and extraction_model columns to configure specialized reasoning endpoints independently of the chat baseline.

The baseline `[[app/models/admin_setting.rb#AdminSetting::SUPPORTED_DECISION_MODELS]]` array pre-registers high-speed decision models (`ScaleDown Classify Latest`, `Jev Latest`, `Perplexity Decider Latest`, `Perplexity Decider Flash Latest`) for closed-set categorization. `[[app/models/admin_setting.rb#AdminSetting::SUPPORTED_EXTRACTION_MODELS]]` pre-registers `ScaleDown Extract Latest` for structured entity extraction. Storing these models in distinct columns guarantees that assigning a specialized decision model to background pipelines never mutates or inflates the cost of conversational summarization.

## Single-pass offered decision and extraction models

AdminSetting lists offered models and decision models through single-pass preloaded catalog lookups to prevent iterative upstream or cache queries.

In `[[app/models/admin_setting.rb#AdminSetting#offered_decision_models_list]]` and `[[app/models/admin_setting.rb#AdminSetting#offered_models_list]]`, the model preloads `[[app/services/llm/open_router_models_service.rb#Llm::OpenRouterModelsService.decision_models]]` (and `catalog_models` when supplied) once prior to scanning the raw stored model list. Each dynamic model ID is evaluated against `[[app/services/llm/model_catalog.rb#Llm::ModelCatalog::OPENROUTER_DECISION_ROUTES]]` and cached decision entries in memory. Meanwhile, `[[app/models/admin_setting.rb#AdminSetting#offered_models_list]]` excludes decision and extraction routes, and `[[app/models/admin_setting.rb#AdminSetting.offered_model_labels]]` reuses a single `AdminSetting` lookup and preloaded catalog arrays across all three model lists.

## Active model and minimum count protection

AdminSetting protects running pipelines by forbidding the removal of active models across summarization, classification, decision, and extraction settings.

`[[app/models/admin_setting.rb#AdminSetting#remove_offered_model!]]` refuses to remove any model currently configured as `summarization_model`, `classification_model`, `decision_model`, or `extraction_model`, raising `ActiveRecord::RecordInvalid`. It also blocks removal if the target model is the final offered model, guaranteeing that the application always retains valid models for all active pipeline stages.

## Removing a model from the list

`AdminSetting::SUPPORTED_MODELS` is the list of baseline models the admin screens offer for `#summarization_model` and `#classification_model`.

A superseded model that still works and costs the same as its replacement stays off the list: an admin choosing it would pay today's price for last year's answer, on every bill summary and every testimony classification.

Removing a model needs no data migration while no admin has moved off the default, because both columns then hold `claude-haiku-5-5`.

Haiku 5.5 stays on the list because it is still the current Haiku, and because it is the column default a fresh database starts from. With dynamic offered models in place, administrators can prune obsolete models from `offered_models` directly in the admin UI without code migrations.

## Why the inclusion validations are conditional

Inclusion validations on summarization_model and classification_model run only if the respective column changed, checking against record.offered_models_list.

Both columns hold a model name, and the list of names they may hold changes as models are added or removed. Rails runs validations on every save, so an unconditional inclusion check meant that one stored name falling off the offered list froze the whole row: an admin editing the other column was refused, with an error about an untouched column.

Checking only the column that changed keeps the guard where it works — a newly submitted name is rejected unless it is in `record.offered_models_list` — while letting the operator update other settings or pick a fresh model. Evaluating `record.offered_models_list` directly on the instance also avoids calling `AdminSetting.singleton` or querying the database during empty-table initialization.

The stored name continues operating in the meantime: `AdminSetting.stored_model?` recognizes active models in the database even if unlisted in `offered_models`, and `Admin::LlmSettingsController` presents stored models clearly so operators know what is currently running.

## Resolving stored models when the catalog is cold

AdminSetting.stored_model? verifies whether a model ID is currently offered or stored in the database, allowing downstream resolution even if cache is cold.

`AdminSetting.stored_model?(model_id)` evaluates whether the identifier matches `offered_models`, `summarization_model`, `classification_model`, `decision_model`, or `extraction_model`. This ensures `Llm::ModelCatalog` and `Llm::RouteResolver` can resolve routes for active models even when `Rails.cache` for `Llm::OpenRouterModelsService` is expired or OpenRouter API access is temporarily interrupted.

## Why the creating migration hardcodes the seed value

`db/migrate/20260528000001_create_admin_settings.rb` seeds the row's `summarization_model` with the literal string `"claude-haiku-5-5"`, not a reference to `AdminSetting::SUPPORTED_MODELS`.

`SUPPORTED_MODELS` changes over time, as the section above describes — a migration that read through it would have its seed value retroactively rewritten by a future edit to the constant, on any database that runs the migration after that edit. The literal freezes what was actually migrated, independent of whatever the constant holds by the time someone runs it.

## Why the retired-model tests write the column directly

Reproducing a stored-but-no-longer-offered model requires writing straight to the column with `update_column`, bypassing validation.

Writing through `update!` would trigger the inclusion check against `record.offered_models_list`, which exists specifically to reject newly assigned unoffered models unless `offered_models` is first mutated to include and then remove the retired name. Writing directly with `update_column` reaches the exact database state left behind when an active model is retired from the baseline list (`claude-sonnet-4-6` is an example of such a model) without mutating `offered_models`.

## Why classification has its own column instead of reusing summarization

`Testimony::AttachmentClassifier` reads `#classification_model`, a separate column from `#summarization_model`, on purpose.

Classifying is a simple judgment made in bulk over every candidate attachment, so sharing one setting with summarization would mean that choosing a better (more expensive) model for bill summaries silently raised the price of every attachment classification too. Both columns draw from the same `SUPPORTED_MODELS` list, but hold independent values.

## Why AdminSetting enforces its own one-row rule twice

`AdminSetting` is meant to hold exactly one row, ever.

The creating migration's `first_or_create!` (see below) means seeding never inserts a duplicate, and `.singleton`'s own `first_or_create!` call means two processes both calling it at application boot cannot both create a row. Neither of those covers every caller, though — `AdminSetting.create!` in a test, a one-off console session, or code written later could still insert a second row directly. `validate :enforce_singleton` refuses any new record while one already exists, so the one-row rule holds everywhere in the app, not only through the paths that remembered to check first.

`.singleton` itself creates the row with the cheapest supported model (`SUPPORTED_MODELS.first`, Haiku) if none exists, as a fallback for a row deleted by hand — the ordinary path is the migration's seed, which runs once when migrations run.

## Frontend: ModelSelectField.tsx and supportedModel.ts

`ModelSelectField.tsx` is shared by both LLM settings dropdowns so the aria wiring (label, invalid, describedby) exists in one place, not two that could drift apart.

`ModelSelectField` uses the searchable `Combobox` component, passing model IDs as search keywords so operators can filter by either provider title or exact model identifier. `SupportedModel#selectable` (`supportedModel.ts`) is false when a model is no longer on the allowed list but the row still holds it — shown so the operator can see what's running, disabled in the combobox because picking it would be refused.

## Why the seed uses first_or_create!, not find_or_create_by!

Seeding a singleton row with `find_or_create_by!(summarization_model: ...)` searches on the model value rather than row existence.

Once an admin has upgraded the singleton away from the seeded default, a later run of the same migration (`db:prepare` on a fresh clone, `db:migrate:redo`, and similar) would search for a row matching the seed value, find none, and insert a second row — breaking the singleton. `first_or_create!` with no condition searches for the first row of any shape, returns it unchanged if one exists, and only inserts the default attributes on a truly empty table.

## Clearing reasoning effort on non-reasoning models

AdminSetting clears summarization and classification reasoning effort attributes whenever the corresponding model does not support reasoning.

When an administrator switches a model from a reasoning-capable model (such as Opus Latest) to a non-reasoning model (such as `claude-haiku-5-5`), the reasoning effort controls are hidden in the settings UI. Normalizing non-blank effort attributes to `nil` during validation (while checking `stored_model?` on the in-memory `AdminSetting` instance when the OpenRouter catalog cache is cold) prevents stale reasoning effort values from lingering on the record without triggering outbound catalog lookups when effort is already blank.

