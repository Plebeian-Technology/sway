---
lat:
  mode: explanation
---

# Why deploy build values need both an ARG and an ENV

Every installation-specific value the application asks for at boot has to reach BOTH the image build and the running container. Getting it wrong costs two failed deploys, and neither failure says what is wrong.

## Why the build cannot read the deployment file

The Google project name and the bucket names moved out of Ruby constants and into `deploy/config/sway.env`.

That file is deliberately kept out of the image — it names a deployment's cloud account, and this repo is public — so nothing in the build can read them. Without them the build dies:

```
SwayDeployConfig::MissingValue: Sway does not know this value:
  SWAY_GCP_PROJECT_ID
```

## The part that is easy to miss

A build should not need any of this.

It only does because `assets:precompile` is a sprockets-rails task that depends on `environment`, so building the assets starts the whole application in production mode — every initializer, every eagerly loaded class. Four separate values are wanted before a single asset is written, and fixing them one failed build at a time is four more builds.

The container then needs the same values again when it starts, and that failure is worse to read: the deploy waits out its ten-minute timeout and reports only that the container never became healthy — the real error sits in the log of a container that keeps restarting.

## The fix

Each boot-time value needs, in `docker/dockerfiles/production.alpine.dockerfile`'s `build` stage:

- An `ARG` with an empty default, to accept the value from `--build-arg`.
- An `ENV`, to put that value where Ruby actually reads it.

plus a matching entry under `builder.args` in `config/deploy.yml`, and a usable value under `env: clear:` so the running container gets its own copy (the build-stage settings never reach the final image).

`spec/config/deploy_build_values_spec.rb` checks all three, by scanning `app/`, `lib/`, and `config/initializers/` for every `SwayDeployConfig.fetch`/`.require_values!` call and cross-checking the result against the Dockerfile and `config/deploy.yml`.

## How the spec parses the Dockerfile

The spec reads only the Dockerfile's `build` stage: an `ARG` declared in another stage does nothing here, since each stage gets its own, and `build` is the stage that runs `assets:precompile`.

Backslash line continuations are joined before the scan, so a name written on the second line of a multi-line `ARG` still counts as declared by that `ARG`.

`ARG` and `ENV` are then read SEPARATELY, and both are required — they do different jobs, and having one without the other looks fine in the Dockerfile while failing at either the build or the container-start step described above. An `ARG` with no matching `ENV` accepts a value from `--build-arg` and then never puts it in the environment, so the Ruby that asks for it still sees nothing; an `ENV` with no `ARG` hard-codes whatever literal is written in the file. A scan that matched any `NAME=` line regardless of instruction would let an `ENV` line satisfy an `ARG` requirement, so deleting a real `ARG` would still leave the example passing. Two separate scans avoid that: deleting either one makes the spec fail.
