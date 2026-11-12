import { defineConfig } from "vite";
import { devWatchIgnore } from "./vite/devWatchIgnore";
import { retryingSourceMapUpload } from "./vite/retryingSourceMapUpload";
import { sentryReleaseName } from "./vite/sentryReleaseName";
import rails from "rails-vite-plugin";
import ReactPlugin from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { VitePWA } from "vite-plugin-pwa";
import manifestSRI from "vite-plugin-manifest-sri";
import { relative, resolve } from "path";
import { Logger } from "sass";
import { sentryVitePlugin } from "@sentry/vite-plugin";

// @lat: [[dev-server-watching#Whether a build uploads source maps]]
const uploadsSourceMaps = Boolean(
    process.env.SENTRY_AUTH_TOKEN && process.env.SENTRY_ORG && process.env.SENTRY_PROJECT,
);

// Source paths whose built chunks only an admin ever loads.
// @lat: [[admin-chunks-are-not-precached#Why admin chunks are named apart from the rest]]
const ADMIN_SOURCE = /\/app\/frontend\/(pages\/admin\/|components\/admin\/|pages\/BillCreatorPage\.tsx)/;

// True when nothing but an admin surface can reach this chunk.
//
// Rollup only inlines a module into a chunk when no other chunk needs it, so a
// chunk fronted by an admin page holds admin-only code however much it inlined.
// The second arm catches shared chunks with no facade of their own — reachable
// from several admin pages and none other.
const isAdminOnlyChunk = (
    facadeModuleId: string | null | undefined,
    moduleIds: readonly string[] | undefined,
): boolean => {
    if (facadeModuleId && ADMIN_SOURCE.test(facadeModuleId)) return true;

    const appModules = (moduleIds ?? []).filter((id) => id.includes("/app/frontend/"));

    return appModules.length > 0 && appModules.every((id) => ADMIN_SOURCE.test(id));
};

// Which commit this build came from, or undefined when it cannot be told.
const releaseName = sentryReleaseName();

// The address the browser uses to reach this dev server. Caddy terminates TLS
// and forwards the Vite paths here, so the browser never talks to :3036
// directly. rails-vite-plugin builds the URL it writes into tmp/rails-vite.json
// from these, and Rails puts that URL in the script tags — so they decide where
// dev assets are loaded from, not just where the HMR socket connects.
//
// These are functions, and the only calls are in the `command === "serve"`
// branch, so a build never reads either one. scripts/dip/dev.sh is what sets
// them; nothing in config/deploy.yml, .kamal/ or the production dockerfile
// does.
//
// They were called VITE_HMR_HOST and VITE_HMR_PORT. Both parts of that were
// wrong. A name starting with VITE_ is one Vite will write into the browser
// bundle wherever the code asks for it, and these must never go there — they
// describe this machine, not the app. Calling them HMR also undersold them:
// hot reloading is one thing they steer, and the address of EVERY source file
// the page loads is the other.
const devHost = (): string => process.env.SWAY_DEV_BROWSER_HOST ?? "localhost";
const devPort = (): number => Number.parseInt(process.env.SWAY_DEV_BROWSER_PORT ?? "3333", 10);

// The path the hot-reload WebSocket opens on. Caddy routes this one path to
// this server; .dockerdev/Caddyfile has to name the same value.
const HMR_PATH = "/vite-hmr";

// Reload the page when a Rails template or helper changes.
//
// rails-vite-plugin has a `refresh` option for this. It works on a Mac and it
// does not work in the container, which is where this project develops.
//
// Measured, changing one .erb file and watching what the browser is told:
//
//   on the Mac,      the plugin's own refresh   reload arrives
//   in the container, the plugin's own refresh  nothing arrives
//   in the container, the code below            reload arrives
//
// The difference is what each one hands the file watcher. The plugin hands it a
// pattern with a star in it. The code below hands it two real folder names. A
// folder name is a thing the watcher can open; a pattern is not, so nothing
// gets watched and no change is ever noticed. On the Mac the reload still
// arrives, but for an unrelated reason — something else there is already
// watching the whole project — so the pattern is never what makes it work.
//
// Deciding which changed file counts is then a plain string test, which also
// avoids depending on a pattern-matching library.
const RELOAD_WATCH_DIRS = ["app/views", "app/helpers"];

const shouldReload = (relativePath: string): boolean =>
    (relativePath.startsWith("app/views/") && /\.(erb|slim|haml)$/.test(relativePath)) ||
    (relativePath.startsWith("app/helpers/") && relativePath.endsWith(".rb"));

const reloadOnRailsTemplateChange = {
    name: "sway-reload-on-rails-template-change",
    apply: "serve" as const,
    configureServer(server: any) {
        server.watcher.add(RELOAD_WATCH_DIRS.map((dir) => resolve(process.cwd(), dir)));
        server.watcher.on("change", (file: string) => {
            const changed = relative(process.cwd(), file);
            if (shouldReload(changed)) {
                // @lat: [[dev-server-watching#A reload a plugin sends says so]]
                server.config.logger.info(`page reload ${changed} (rails template watcher)`, { timestamp: true });
                server.hot.send({ type: "full-reload", path: "*" });
            }
        });
    },
};

export default defineConfig(({ command }) => ({
    plugins: [
        // refresh: false — its watcher cannot work here; see
        // reloadOnRailsTemplateChange above, which replaces it.
        //
        // buildDir: two verify runs at once share one named volume
        // (public/vite-test), so one run rebuilding mid-flight can overwrite
        // the bundle another run's browser specs are reading. Undefined when
        // unset, so the plugin's own default (vite-test in test mode, vite
        // otherwise) is unchanged for every other invocation (D-18).
        //
        // An empty value counts as unset, matching the Rails half in
        // config/initializers/_vite_build_dir.rb. The plugin resolves this
        // with ??, which keeps "" — the build directory would become public/
        // itself, and Vite empties that directory before it builds.
        rails({
            sourceDir: "app/frontend",
            refresh: false,
            buildDir: process.env.SWAY_VITE_BUILD_DIR || undefined,
        }),
        ReactPlugin(),
        tailwindcss(),
        // Puts integrity + crossorigin on every script, stylesheet and
        // modulepreload tag: the plugin writes a hash into the manifest and
        // RailsVite::TagHelper copies it onto the tag.
        manifestSRI(),
        // Included only when it can actually upload. Passing an undefined token
        // makes the plugin warn and carry on, which is how a build can look
        // successful while Sentry receives nothing.
        ...(uploadsSourceMaps
            ? [
                  sentryVitePlugin({
                      authToken: process.env.SENTRY_AUTH_TOKEN,
                      org: process.env.SENTRY_ORG,
                      project: process.env.SENTRY_PROJECT,
                      // Which build these maps belong to. Left out when this
                      // build cannot tell, rather than sent as a guess — see
                      // vite/sentryReleaseName.ts.
                      ...(releaseName ? { release: { name: releaseName } } : {}),
                      // Tried a few times before this fires — see
                      // vite/retryingSourceMapUpload.ts, which wraps the
                      // upload below.
                      //
                      // A FAILED UPLOAD MUST FAIL THE BUILD. By default the
                      // plugin logs the error and continues, which would leave a
                      // deployable image whose maps were deleted (see the
                      // dockerfile step after assets:precompile) and never
                      // arrived anywhere — no symbolication, discovered during
                      // an incident. Throwing couples the two: an image that
                      // ships without maps is one that uploaded them.
                      errorHandler: (error) => {
                          throw error;
                      },
                  }),
              ]
                  .flat()
                  // Called with one argument on purpose. Array.map hands the
                  // index in as the second one, and the second parameter here
                  // is the retry settings.
                  .map((plugin) => retryingSourceMapUpload(plugin))
            : []),
        VitePWA({
            strategies: "injectManifest",
            // Path is relative to the Vite root, which is the project root.
            srcDir: "app/frontend/service-worker",
            filename: "sw.ts",
            registerType: "prompt",
            // SW asset is served from /vite/sw.js (Vite base) but must control the
            // whole site, so we register it at root scope. Requires the response
            // to carry Service-Worker-Allowed: /, set by ServiceWorkerAllowedMiddleware.
            scope: "/",
            injectManifest: {
                globPatterns: ["**/*.{js,css,html,ico,png,svg,woff2}"],
                // @lat: [[admin-chunks-are-not-precached#Why the precache excludes them]]
                globIgnores: ["assets/admin/**"],
                dontCacheBustURLsMatching: /[.-][a-f0-9]{8,}\./,
            },
            // D-22: public/manifest.json is the authoritative PWA manifest.
            // Disable VitePWA manifest generation to avoid two competing manifests.
            manifest: false,
            devOptions: { enabled: false },
        }),
        reloadOnRailsTemplateChange,
    ],

    server:
        command === "serve"
            ? {
                  open: false,
                  host: "0.0.0.0",
                  port: Number.parseInt(process.env.VITE_PORT ?? "3036", 10),
                  // Fail rather than move to the next free port. Caddy forwards
                  // to a fixed port, so a silent move breaks every asset request
                  // with no error on this side.
                  strictPort: true,
                  // Caddy forwards the browser's Host header unchanged, so this
                  // server sees the public hostname rather than its own.
                  allowedHosts: [...new Set(["localhost", devHost()])],

                  hmr: {
                      // Route HMR WebSocket through Caddy so it works over wss://
                      host: devHost(),
                      clientPort: devPort(),
                      protocol: "wss",
                      // Without this the socket opens at "/", which Caddy sends
                      // to Rails — the handshake then gets a 200 HTML page back
                      // and hot reloading dies silently while the page still
                      // loads. A path of its own is what Caddy can route.
                      path: HMR_PATH,
                  },

                  // DO NOT turn polling back on without reading this.
                  //
                  // Polling means "ask every file whether it changed, over and
                  // over", instead of waiting to be told. This project used to
                  // do that safely, because the old plugin pointed Vite at
                  // app/frontend and nothing else. rails-vite-plugin leaves
                  // Vite pointed at the whole repository, so the same setting
                  // started asking that question of every file in the project:
                  // the built assets, the databases, the phone app, the logs.
                  //
                  // Measured in the container, sitting idle, doing nothing:
                  // polling on = 439% of one core. Polling off = 0%.
                  // That work was taken from serving files, so a page that
                  // should arrive in a fifth of a second took eight seconds.
                  //
                  //   page load, /bills   polling on   8221 ms
                  //   page load, /bills   polling off   220 ms
                  //
                  // Waiting to be told works here: a change to a React file and
                  // a change to a view file both reached the browser with
                  // polling off. If hot reloading ever stops noticing edits,
                  // the fix is NOT to switch this back on. Watch only the two
                  // or three folders that hold source, and leave the rest of
                  // the repository alone.
                  watch: {
                      usePolling: false,
                      // @lat: [[dev-server-watching#Why a machine-written file must not be watched]]
                      ignored: devWatchIgnore(process.cwd()),
                  },
                  cors: true,
              }
            : undefined,

    resolve: {
        alias: {
            // "@" is set by rails-vite-plugin from sourceDir.
            "app/frontend": resolve(process.cwd(), "app", "frontend"),
        },
    },

    // Prevent Sass warnings from being logged and cluttering terminal
    css: {
        preprocessorOptions: {
            scss: {
                logger: Logger.silent,
                quietDeps: true,
            },
        },
    },

    // Prevent warnings being logged when using vite + material UI
    // https://github.com/vitejs/vite/issues/15012#issuecomment-1815854072
    build: {
        // "hidden" still WRITES the .map files. It only stops the
        // `//# sourceMappingURL=` comment being appended to the JavaScript, which
        // is what made them discoverable — Rails serves public/, so devtools and
        // Sentry's scraper could both pull 140 MB of readable frontend source off
        // the server. Sentry does not need the comment: the plugin stamps a debug
        // ID into both the bundle and the map and matches on that.
        sourcemap: "hidden",
        rollupOptions: {
            output: {
                // @lat: [[admin-chunks-are-not-precached#Why admin chunks are named apart from the rest]]
                chunkFileNames: (chunk: { facadeModuleId?: string | null; moduleIds?: readonly string[] }) =>
                    isAdminOnlyChunk(chunk.facadeModuleId, chunk.moduleIds)
                        ? "assets/admin/[name]-[hash].js"
                        : "assets/[name]-[hash].js",
            },
            onLog(level, log, handler) {
                if (log.cause && (log.cause as any).message === "Can't resolve original location of error.") {
                    return;
                }
                handler(level, log);
            },
        },
    },
}));
