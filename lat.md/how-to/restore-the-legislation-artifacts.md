---
lat:
  mode: how-to
---
# Restore the legislation artifacts

Copy the pipeline's artifact tree, or one root of it, out of the backup bucket and into a directory you name. The task never guesses the directory and refuses to write the live tree; [[legislation-artifact-backup]] holds the reasoning.

Two things have to be true before any of this works: the machine has
`SWAY_GCS_BUCKET_LEGISLATION` set (`deploy/config/sway.env`, or the environment),
and its Google credentials can read that bucket. A developer machine usually has
neither, and the task fails at the first listing rather than half way through.

## Steps

The whole sequence, from an empty directory to a tree the pipeline can read. Steps 1 to 3 fetch; steps 4 and 5 check and place what arrived.

1. Choose a destination outside the artifact tree, on a disk with room for it — the tree is several gigabytes, so the restore takes time. A path inside the repository checkout, such as `tmp/restored-artifacts`, is visible from both the host and the container; a path that exists only inside the container disappears with it.

2. Run the restore task, passing `DESTINATION` as a trailing rake argument rather than as an environment prefix — `dip` forwards a host variable into the container only when `dip.yml` names it, so a prefix is dropped and the task aborts asking for the destination it was already given:

    ```bash
    dip run bundle exec rake legislation:artifacts:restore \
      DESTINATION=tmp/restored-artifacts
    ```

3. Narrow the fetch with `ONLY=` when the whole tree is not wanted. It takes one bucket key — `bills/raw`, `bills/text`, `hearings`, `law`, `diffs`, `prompt_dumps` or `attachments` — and restricts the listing to that root, while still writing it at its usual place under the destination:

    ```bash
    dip run bundle exec rake legislation:artifacts:restore \
      DESTINATION=tmp/restored-artifacts ONLY=diffs
    ```

    Add `PREFIX=` to read a prefix other than this environment's default (`legislation/<environment>/`), which is how a copy taken under a verification prefix is read back.

4. Read the counts the task prints. `listed_count` is what the bucket held under the prefix, `downloaded_count` and `downloaded_bytes` are what arrived, `failed_count` and `skipped_unsafe_count` are what did not. A `failed_count` above zero also prints one line per object naming the reason; the task exits non-zero only when the listing itself failed, so check these counts even on a clean exit.

5. Point the pipeline at the result to confirm it is usable. A full restore reproduces the ordinary on-disk layout, so the destination works directly as a legislation root. `LEGISLATION_ROOT` is not a rake argument, so set it inside the container's own shell — a prefix in front of `dip run` never arrives:

    ```bash
    dip run bash -lc 'LEGISLATION_ROOT=tmp/restored-artifacts \
      bundle exec rails runner "puts Legislation::Paths.bills_text.children.size"'
    ```

## When the task refuses the destination

The task stops with `LiveTreeRefused` before it lists anything when the destination overlaps the live tree, and names both the path it was given and the root it clashes with.

1. Treat the refusal as correct and pick a destination outside the tree. This holds even when the live tree is empty or gone: the check compares paths, not contents.

2. Move the restored files into place yourself once you have read the counts and are satisfied with what arrived. A move is a separate, deliberate act, and it is the only supported way to put a restore back over the live tree from the command line.

3. Reach for `Legislation::ArtifactRestoreService.new(destination: …, allow_live_tree: true)` in a console only when overwriting the live tree in place is genuinely what you mean. The rake task does not offer that keyword, and the tree it would overwrite has one copy.
