import { defineConfig } from "vite";
// import RubyPlugin from "vite-plugin-ruby"
import RailsPlugin from "vite-plugin-rails";
import ReactPlugin from "@vitejs/plugin-react";
import { readFileSync } from "fs";
import { resolve } from "path";

export default defineConfig({
    plugins: [RailsPlugin(), ReactPlugin()],

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
                    charts: ["chart.js", "react-chartjs-2"],
                    copy: ["copy-to-clipboard"],
                    dates: ["react-datepicker"],
                    emoji: ["emoji-name-map"],
                    forms: ["formik", "yup"],
                    icons: ["react-icons", "react-social-icons"],
                    lodash: ["lodash"],
                    markdown: ["react-markdown", "remark-gfm"],
                    // select: ["react-select"],
                    text_area: ["react-textarea-autosize"],
                    toast: ["react-hot-toast"],
                },
            },
        },
    },
});
