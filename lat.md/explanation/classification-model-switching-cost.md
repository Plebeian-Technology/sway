---
lat:
  mode: explanation
---

# Why switching the classification model has a one-time cost

Changing the classification model in `/admin/llm_settings` does not just change what the *next* call costs.

`TestimonyAttachmentClassification.for_verdict` keys its cache on `(attachment_id, model, prompt_version)`, so every attachment already classified under the old model stops matching: the whole cache of settled verdicts is thrown away, and every candidate attachment is re-classified — and re-billed — on the next run.

The `ModelSelectField` description for `classification_model` in `LlmSettings.tsx` names this explicitly (B2-IN-05). An earlier version of the copy explained only the per-call cost, so an operator comparing tiers was reading an incomplete price: a higher tier looks cheap per call but re-classifying the whole backlog once is a one-time charge on top, and this setting runs many calls per bill where the summarization model runs once.

No such switching cost applies to `summarization_model` — bill summaries have no equivalent verdict cache — so the settings page and its tests deliberately check that the summarization description does NOT carry the same "re-classifies" language.

## Why CLASSIFIER_MODEL is independent of the summarization default

`Testimony::AttachmentClassifier::CLASSIFIER_MODEL` is the default and fallback model used when `AdminSetting#classification_model` can't be read.

It is deliberately independent of `AdminSetting#summarization_model` — this is a high-volume, low-judgement call suited to Haiku, and an admin moving summaries to Opus should not silently multiply classification cost too.

Do not add `effort`, `thinking`, or sampling params to this call path: Haiku 5.5 rejects `effort` with an HTTP 400, and `generate_structured` already omits all three.
