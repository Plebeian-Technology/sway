---
lat:
  mode: explanation
---

# Why write_keyfile controls its own disk writes

`SwayGoogleCloudStorage.write_keyfile` skips a no-op rewrite of the
service-account key and creates its own parent directory before writing,
rather than assuming either condition already holds.

## The path is a method, and the client is memoized

Where the key file lives is answered by a method rather than a constant, and
the storage client is built once per process.

A method is what lets the write-or-skip logic and its own specs point at the
same answer, so a spec can redirect it to a temporary directory instead of
writing into the checkout. The client was once rebuilt on every call, which
re-ran the class-level key file write each time; memoizing it means the write
happens once, which is the whole point of skipping a redundant one.

## Skipping redundant writes

Before a skip check existed, `write_keyfile` rewrote the raw private key on
every call to `.credentials` — at boot and on every use of storage — because
the value was never cached or compared against what was already on disk.

`write_keyfile` now skips the write when the file already holds exactly the
payload it was about to write, but still re-applies file permissions (mode
`0600`; it used to be world-readable `0644`) even on the skip path, since
permissions can drift independently of content. `.credentials` also used to
print three `puts` sanity checks to stdout on every call, including in
production; it now prints nothing.

## Creating the directory at write time

The keyfile's parent directory used to exist in the build image only
because a tracked `config/keys/.gitkeep` file was negated in the
dockerignores, so `File.open(path, "w")` always found somewhere to write.

That was an invisible coupling: nothing at the write site said the
directory depended on a separate, unrelated file surviving into the build
context. It broke silently the moment the keyfile moved from `config/keys/`
to `keys/` at the repo root, because the new location had no equivalent
tracked placeholder. `write_keyfile` now calls `FileUtils.mkdir_p` on the
target directory before writing, so the write no longer depends on any file
having been committed elsewhere to make the directory exist first.

## Creating the directory needs a writable parent

`FileUtils.mkdir_p` moved the dependency rather than removing it: the call
succeeds only where the process may create a directory.

The production image runs as `rails:rails` and leaves `/rails` owned by
root, handing the `rails` account only the subdirectories it must write —
`config`, `db`, `public`, `log`, `tmp`, `storage`. A recursive `chown` over
the whole tree was removed earlier on purpose, so widening ownership to fix
this is not open.

While the keyfile lived at `config/keys/`, its parent was one of those
writable directories and the boot-time write landed. The move to `keys/` at
the repo root put it directly under root-owned `/rails`, and the first
deploy afterwards died in the Active Storage initializer with
`Errno::EACCES: Permission denied @ dir_s_mkdir - /rails/keys` before Rails
finished starting.

The image therefore creates `keys/` and gives it to `rails`, at mode `0700`
to match the `0600` key inside it. Nothing is committed to hold the
directory open — `/keys/` is excluded from both build contexts precisely so
a real key can never enter an image — so the Dockerfile is the only place
this can be arranged, and
`spec/config/production_image_keyfile_dir_spec.rb` fails if a later move of
the keyfile leaves its directory behind.
