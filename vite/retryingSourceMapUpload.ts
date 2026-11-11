import type { Plugin } from "vite";

// Try the Sentry source-map upload again when it fails.
//
// THIS DOES NOT CHANGE THE RULE that a failed upload fails the build. The
// Sentry plugin in vite.config.ts is given an errorHandler that rethrows, and
// the production dockerfile deletes the .map files only on a build that got
// past it — so an image that ships without maps is one that sent them. This
// changes how quickly that rule gives up.
//
// A deploy was lost on 2026-08-06 to a single name lookup that did not answer:
//
//   error: API request failed
//     1: [6] Could not resolve hostname (Could not resolve host: us.sentry.io)
//
// The frontend had already built. One unlucky second is not the outage the rule
// exists to catch, and it stopped the deploy anyway.
//
// SENDING AGAIN IS SAFE, and is not a quiet no-op that would let a build delete
// maps it never sent. The plugin's writeBundle hook is written to run more than
// once in one build — its own source says so, because build tools like
// @vitejs/plugin-legacy call it repeatedly. Each run finds the .map files on
// disk again, copies them into a new temporary folder and sends that folder.
// The maps themselves are untouched until the dockerfile deletes them, long
// after this.

export const UPLOAD_ATTEMPTS = 3;
export const WAIT_BETWEEN_UPLOAD_ATTEMPTS_MS = 3_000;

interface RetryOptions {
    attempts?: number;
    waitMs?: number;
    /** Where the warning between attempts goes. Swapped out in tests. */
    warn?: (message: string) => void;
}

/**
 * Wrap a Vite plugin so its writeBundle hook is retried before it is allowed to
 * fail. Any other plugin is returned untouched.
 */
export const retryingSourceMapUpload = (plugin: Plugin, options: RetryOptions = {}): Plugin => {
    const attempts = options.attempts ?? UPLOAD_ATTEMPTS;
    const waitMs = options.waitMs ?? WAIT_BETWEEN_UPLOAD_ATTEMPTS_MS;
    const warn = options.warn ?? ((message: string) => console.warn(message));

    const upload = plugin.writeBundle;

    // Only a plain function can be wrapped. A later version of the plugin could
    // hand this hook over as { handler, order } instead, and then the retries
    // would stop happening with nothing to show for it — a switch that is off
    // and still looks on. app/frontend/__tests__/sentryUploadRetry.test.ts
    // fails when that shape changes.
    if (typeof upload !== "function") {
        return plugin;
    }

    return {
        ...plugin,
        writeBundle: async function (this: ThisParameterType<typeof upload>, ...args: Parameters<typeof upload>) {
            for (let attempt = 1; ; attempt += 1) {
                try {
                    return await upload.apply(this, args);
                } catch (error) {
                    if (attempt >= attempts) {
                        throw error;
                    }

                    warn(
                        `[sentry] source map upload failed on attempt ${attempt} of ${attempts}. ` +
                            `Waiting ${waitMs / 1000}s, then trying again. ` +
                            String(error),
                    );
                    await new Promise((resolve) => setTimeout(resolve, waitMs));
                }
            }
        },
    };
};
