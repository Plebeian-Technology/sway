---
mode: explanation
summary: "Explains why .rubocop.yml pins AllCops::CacheRootDirectory into the repo's own tmp/, and why the spec resolves the ERB value the way rubocop itself does rather than matching the file's text."
status: agent-extracted
related: []
---

# Why `.rubocop.yml` pins its cache root into the repo

Rubocop's default cache root sits under `$HOME`. Where the operating
system protects that path (macOS TCC-locks several cache directories),
every subdirectory of it is unreadable, and rubocop's cleanup step — which
globs `*/*/*` across the WHOLE root before it inspects anything — takes
the run down having checked no files at all. Every
subdirectory under the default root can refuse both reading and removal, so
there is nothing to delete and no permission to grant; the regression
gate's rubocop lane then spends minutes and reports no result.

`AllCops::CacheRootDirectory` is set to an absolute path inside the
repo's own `tmp/` instead — writable without asking the OS for anything,
and already ignored by git.

## Why the spec resolves the value the way rubocop does, not by matching text

`AllCops::CacheRootDirectory` in `.rubocop.yml` is an ERB expression, not a
plain string, so reading the file's text literally would pass even if the
expression evaluated to something useless. `spec/config/rubocop_cache_root_spec.rb`
resolves it the same way rubocop's `ConfigLoader` does instead.

Rubocop evaluates this file's ERB with the working directory already
changed to the file's own directory
(`ConfigLoader#load_yaml_configuration`). A second, lighter read rubocop
performs elsewhere (to place the server directory) does NOT change
directory first — so a cache-root expression that reads the current
working directory can give two different answers depending on which of
rubocop's own code paths reads it. `#cache_root_from` in the spec
reproduces both read shapes (from the repo root, and from a subdirectory)
and asserts they agree, which is exactly the drift that once caused a
stray `app/tmp/rubocop_cache` directory to appear.
