import { resolve } from "node:path";

import { build } from "vite";
import tailwindcss from "@tailwindcss/vite";
import { describe, expect, it } from "vitest";
import { THEME_NAMES, themeCss } from "app/frontend/styles/themes/__tests__/themeFiles";
import { uniqueColourValue } from "./colourNotation";

// @lat: [[theme-test-suite-silent-failure-guards#CSS bundle: a nested @import url() that Tailwind v4 silently dropped]]

// The shape of a built CSS file. Written out here so the test does not depend on
// rollup's own types resolving under the test tsconfig.
interface BuiltChunk {
    type: string;
    fileName: string;
    source?: string | Uint8Array;
}
interface BuiltOutput {
    output: readonly BuiltChunk[];
}

// @lat: [[theme-test-suite-silent-failure-guards#CSS bundle: a nested @import url() that Tailwind v4 silently dropped]]

// @lat: [[theme-test-suite-silent-failure-guards#CSS bundle: a nested @import url() that Tailwind v4 silently dropped]]
const proofValueFor = (theme: string): string =>
    uniqueColourValue(`${theme}.css`, themeCss(theme), THEME_NAMES.filter((name) => name !== theme).map(themeCss));

describe("theme CSS bundling", () => {
    it("finds a value unique to each theme file to key that theme on", () => {
        // proofValueFor throws when a theme has no colour of its own, so this
        // names the theme instead of failing inside the slow build below.
        const values = THEME_NAMES.map((theme) => [theme, proofValueFor(theme)] as const);

        expect(new Set(values.map(([, hex]) => hex)).size).toBe(THEME_NAMES.length);
        expect(THEME_NAMES.length).toBeGreaterThan(1);
    });

    it("inlines every theme's tokens into the built CSS", async () => {
        const root = resolve(process.cwd(), "app/frontend");

        const result = await build({
            root,
            configFile: false,
            logLevel: "silent",
            plugins: [tailwindcss()],
            build: {
                write: false,
                cssMinify: false,
                rollupOptions: {
                    input: resolve(root, "styles/application.css"),
                },
            },
        });

        // build() can hand back RollupOutput, RollupOutput[] or RollupWatcher.
        // One build that is not watching for changes is a single RollupOutput.
        const outputs = (Array.isArray(result) ? result : [result]) as unknown as BuiltOutput[];

        const css = outputs
            .flatMap((bundle) => bundle.output)
            .filter((chunk) => chunk.type === "asset" && chunk.fileName.endsWith(".css"))
            .map((chunk) => String(chunk.source ?? ""))
            .join("\n");

        expect(css.length).toBeGreaterThan(0);

        // Each theme's CSS block has to survive the chain of imports
        // (application.css → tokens.css → themes/<theme>.css), for EVERY theme.
        // Files get dropped one at a time, so checking only two themes let the
        // other four vanish in silence.
        const missing = THEME_NAMES.flatMap((theme) => {
            const problems: string[] = [];
            if (!css.includes(`[data-theme="${theme}"]`)) problems.push(`${theme}: light selector block`);
            if (!css.includes(`[data-theme="${theme}"].dark`)) problems.push(`${theme}: dark selector block`);
            // A colour that appears ONLY inside this theme's own file — proof
            // the nested @import was inlined, not dropped.
            const proof = proofValueFor(theme);
            if (!css.includes(proof)) problems.push(`${theme}: its own colour ${proof}`);
            return problems;
        });
        expect(missing).toEqual([]);

        // The blocks that follow the operating system's light/dark setting
        // (prefers-color-scheme) must survive too.
        expect(css).toContain("prefers-color-scheme");

        // @lat: [[theme-test-suite-silent-failure-guards#CSS bundle: a nested @import url() that Tailwind v4 silently dropped]]
        expect(css).toContain("var(--space-unit)"); // --spacing → p-*/m-*/gap-*
        expect(css).toContain("var(--type-small)"); // --text-sm → text-*
        expect(css).toContain("var(--radius-md)"); // --radius-md → rounded-md
        expect(css).toContain("var(--weight-display)"); // --font-weight-black → font-black
        expect(css).toContain("var(--tracking-caps)"); // --tracking-widest → tracking-widest
    }, 60_000);
});
