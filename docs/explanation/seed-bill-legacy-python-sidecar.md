---
mode: explanation
summary: "Why SeedBill kept its Python-sidecar-era public API after the pipeline moved natively into Rails."
status: agent-extracted
related: []
---

# Why SeedBill kept its old public API

`SeedBill` seeds Baltimore bills by running the legislation pipeline
(`RunLegislationPipelineJob`) synchronously, right inside Rails. An older
version delegated to a Python sidecar; that path was deleted, and this class
kept the same public API (`SeedBill.run(sway_locales, force:, refresh:)`) so
the `db:seed` and `db:seed:force` entry points did not have to change.
