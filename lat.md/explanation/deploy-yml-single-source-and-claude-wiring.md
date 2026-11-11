---
lat:
  mode: explanation
---

# Why spec/config/deploy_yml_spec.rb pins two separate invariants

Explains why config/deploy.yml's machine address may appear only in its top ERB block, and why the Claude API routing wiring (env.clear.LLM_PROVIDER and env.secret ANTHROPIC_API_KEY) is checked directly rather than trusted.

## Why the machine's address may appear only once, in the top block

Consolidating the Pi's machine address into one Ruby block at the top of `config/deploy.yml` is only worth anything while it STAYS in one place.

The obvious way to lose that is the helpful-looking edit: someone needs a different machine for one role, writes the address in directly, and it works — so nothing complains, and the next person moving machines has two places to find instead of one. That is how the address drifted to appearing in six places before it was consolidated, and the notes written for that switch-over only found four of the six.

`"names no machine anywhere except the block at the top"` scans the file body (with the ERB header stripped) for any line matching an IP address or a `/media`/`/mnt` disk path outside that block. Commented lines are allowed through deliberately: the file carries a spare Tailscale address and Kamal's own template examples in comments, and neither is read by anything, so flagging them would make the check noisy without catching a real regression.

## Why the Claude API routing wiring is checked directly

The production Kamal deploy config has to wire up both halves of Claude API routing, and a later edit to either line breaks it silently rather than loudly:

- `env.clear.LLM_PROVIDER` must be `"claude"` so the production
  container's `GenerateBillSummaryJob#perform` reads
  `LLM_PROVIDER=claude` and sends the request through
  `Llm::ClaudeAdapter` (see `docs/explanation/llm-client-provider-selection.md`
  for what happens inside `Llm::Client.build`). Without that line the
  container starts with `LLM_PROVIDER` unset, `Llm::Client.build` falls
  back to `llamacpp`, and every job fails outright on the Pi, which runs
  no llama.cpp server.
- `env.secret` must list `"ANTHROPIC_API_KEY"` so Kamal's
  `.kamal/secrets-common` lookup can pull the key out of Bitwarden and
  pass it into the container at deploy time.

If a later edit to `deploy.yml` drops either line, this spec fails before the change ever reaches the Pi — the alternative is a job that fails silently in production with no local reproduction, since dev and test both stub the LLM adapter.
