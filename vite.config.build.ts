import { sentryVitePlugin } from "@sentry/vite-plugin";
import { defineConfig } from "vite";
import ReactPlugin from "@vitejs/plugin-react";
import { resolve } from "path";
import RailsPlugin from "vite-plugin-rails";

export default defineConfig({
    plugins: [
        RailsPlugin(),
        ReactPlugin(),
        sentryVitePlugin({
            authToken: process.env.SENTRY_AUTH_TOKEN,
            org: process.env.SENTRY_ORG,
            project: process.env.SENTRY_PROJECT,
        }),
    ],

    resolve: {
        alias: {
            "app/frontend": resolve(process.cwd(), "app", "frontend"),
        },
    },

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
            output: {
                manualChunks: {
                    address_autocomplete: ["use-places-autocomplete", "@react-google-maps/api"],
                    auth: ["@github/webauthn-json"],
                    calendar: ["date-fns", "@mui/x-date-pickers", "@mui/material", "@emotion/react", "@emotion/styled"],
                    charts: ["chart.js", "react-chartjs-2"],
                    copy: ["copy-to-clipboard"],
                    emoji: ["emoji-name-map"],
                    forms: ["use-inertia-form", "yup"],
                    icons: ["react-icons", "react-social-icons"],
                    lodash: ["lodash"],
                    markdown: ["react-markdown", "remark-gfm"],
                    text_area: ["react-textarea-autosize"],
                    toast: ["react-hot-toast"],
                    sentry: ["@sentry/react"],
                },
            },
        },
    },
});
