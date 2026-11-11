import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import { resolve } from "path";

export default defineConfig({
    plugins: [react()],
    test: {
        environment: "jsdom",
        globals: true,
        setupFiles: ["./app/frontend/__tests__/setup.ts"],
        globalSetup: ["./app/frontend/__tests__/assert-pinned-node.ts"],
        include: [
            "app/frontend/**/__tests__/**/*.test.{ts,tsx}",
            "app/frontend/**/*.test.{ts,tsx}",
            "scripts/eval/__tests__/**/*.test.{ts,tsx}",
        ],
        exclude: ["**/node_modules/**"],
        alias: {
            "@": resolve(process.cwd(), "app", "frontend"),
            "app/frontend": resolve(process.cwd(), "app", "frontend"),
            // Stub virtual modules provided by vite-plugin-pwa (not available in vitest/jsdom)
            "virtual:pwa-register/react": resolve(
                process.cwd(),
                "app/frontend/__tests__/__mocks__/virtual-pwa-register-react.ts",
            ),
            "virtual:pwa-register": resolve(process.cwd(), "app/frontend/__tests__/__mocks__/virtual-pwa-register.ts"),
        },
    },
});
