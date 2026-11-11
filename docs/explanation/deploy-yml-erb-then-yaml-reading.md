---
mode: explanation
summary: "Explains why every reader of config/deploy.yml must render it through ERB before parsing it as YAML, and what breaks for a reader that doesn't."
status: agent-extracted
related: [deploy-config-lookup-order]
---

<!-- vale Vale.Spelling = NO -->

# Why config/deploy.yml must be read as ERB, then YAML

Kamal reads `config/deploy.yml` by running it through ERB and THEN reading
the result as YAML. Anything else that reads that file has to do the same.

## Why it needs checking

Reading it as plain YAML appeared to work for a long time, because every ERB
tag in the file sat inside quotes — so YAML saw an ordinary string and handed
back something that looked like an answer. Moving the machine's address into
the file's one Ruby block wrote `host: <%= sway_host %>` with
no quotes, and a plain reader started handing back those sixteen characters
AS THE ADDRESS.

The one real reader was `scripts/provision-litestream-key.sh`, which sends a
cloud-storage credential to that address. It would have tried to reach a
machine named `<%= sway_host %>`, failed, and stopped the deploy — loud, and
not a leak, but the first time anyone would have seen it was mid-deploy.

Nothing failed when that reader broke. The address it resolved was never
checked by anything, which is the actual gap `spec/config/deploy_yml_readers_spec.rb`
closes: it runs the real script and asserts its resolved target is a real
address, not an unrendered ERB tag, and scans the repo for any other reader
that parses `deploy.yml` as YAML without rendering it through ERB first.

Read it the way Kamal does:

```ruby
YAML.load(ERB.new(File.read("config/deploy.yml")).result, aliases: true)
```
