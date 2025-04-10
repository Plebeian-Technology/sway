import { defineConfig } from "vite";
import RailsPlugin from "vite-plugin-rails";
import ReactPlugin from "@vitejs/plugin-react";
import visualizer from "rollup-plugin-visualizer";
import { readFileSync } from "fs";
import { resolve } from "path";

export default defineConfig({
    plugins: [
        RailsPlugin(),
        ReactPlugin(),
        // visualizer(),
        // sentryVitePlugin({
        //     authToken: process.env.SENTRY_AUTH_TOKEN,
        //     org: "sway-a6",
        //     project: "sway",
        // }),
    ],

    server: {
        open: false,

        https: {
            cert: readFileSync("./config/ssl/cert.pem"),
            key: readFileSync("./config/ssl/key.pem"),
        },

        watch: {
            usePolling: true,
        },
    },
    resolve: {
        alias: {
            "app/frontend": resolve(process.cwd(), "app", "frontend"),
        },
    },

    // Prevent Sass warnings from being logged and cluttering terminal
    css: {
        preprocessorOptions: {
            scss: {
                api: "modern-compiler", // or 'modern'
                quietDeps: true,
            },
        },
    },

    // Prevent warnings being logged when using vite + material UI
    // https://github.com/vitejs/vite/issues/15012#issuecomment-1815854072
    build: {
        sourcemap: true,
        outDir: "build",
        rollupOptions: {
            onLog(level, log, handler) {
                if (log.cause && (log.cause as any).message === "Can't resolve original location of error.") {
                    return;
                }
                handler(level, log);
            },
        },
    },
});
