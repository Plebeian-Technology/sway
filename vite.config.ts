import { defineConfig } from "vite"
import RubyPlugin from "vite-plugin-ruby"
import ReactPlugin from "@vitejs/plugin-react"
import { readFileSync } from "fs"
import { resolve } from "path"

export default defineConfig({
    plugins: [RubyPlugin(), ReactPlugin()],

    server: {
        open: false,

        https: {
            cert: readFileSync("./config/ssl/cert.pem"),
            key: readFileSync("./config/ssl/key.pem"),
        },
    },
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
                if (
                    log.cause &&
                    (log.cause as any).message ===
                        "Can't resolve original location of error."
                ) {
                    return
                }
                handler(level, log)
            },
        },
    },
})
