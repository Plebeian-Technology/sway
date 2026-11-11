// The name Sentry files this build's source maps under.
//
// WHAT IT FIXES. The Source Maps page in Sentry read "Found in Releases:
// undefined". The plugin tries to work the name out on its own, falls back to
// asking git for the current commit, and the build image has no git command —
// so it ended up with the word "undefined" and used it. Nothing was broken by
// that. Sentry pairs a map with the code it came from by an id stamped into
// both files, never by the release name. It only made the list unreadable once
// more than one build was in it, because every build had the same name.
//
// WHERE THE VALUE COMES FROM. scripts/deploy.sh works out the commit before the
// image is built and config/deploy.yml passes it in as a build setting. The
// same value is already baked into the running image for Sway::Release, so the
// version shown in the app and the version shown in Sentry are one value, not
// two that can disagree.
//
// A PLAIN `docker build` HAS NO VALUE, and then this sends no name at all
// rather than a made-up one. A wrong name is worse than none: it would file one
// machine's maps under another build.
//
// SIDE EFFECT WORTH KNOWING. The plugin also writes the name into the bundle,
// so the browser tags every error it sends with the same release. That is the
// plugin's own default and it is what makes the release page show the errors
// and the maps together.

export const sentryReleaseName = (env: NodeJS.ProcessEnv = process.env): string | undefined => {
    const sha = env.SWAY_RELEASE_SHA?.trim();

    return sha ? sha : undefined;
};
