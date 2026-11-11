import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

// @lat: [[navigation-placeholder-tracer#Why @inertiajs/core is a pinned devDependency rather than a caret dependency]]

const REPO_ROOT = resolve(__dirname, "../../../..");

const readJson = (...segments: string[]): Record<string, never> =>
    JSON.parse(readFileSync(resolve(REPO_ROOT, ...segments), "utf8"));

describe("the @inertiajs/core devDependency pin", () => {
    const manifest = readJson("package.json") as unknown as {
        devDependencies: Record<string, string>;
        dependencies: Record<string, string>;
    };
    const installedReact = readJson("node_modules", "@inertiajs", "react", "package.json") as unknown as {
        version: string;
        dependencies: Record<string, string>;
    };
    const installedCore = readJson("node_modules", "@inertiajs", "core", "package.json") as unknown as {
        version: string;
    };

    it("names the exact version @inertiajs/react itself depends on", () => {
        expect(manifest.devDependencies["@inertiajs/core"]).toBe(installedReact.dependencies["@inertiajs/core"]);
    });

    it("resolves the same @inertiajs/core copy that @inertiajs/react runs, so the types describe the live router", () => {
        expect(installedCore.version).toBe(installedReact.dependencies["@inertiajs/core"]);
    });

    it("stays a devDependency, because every app use of it is an erased `import type`", () => {
        expect(manifest.devDependencies).toHaveProperty("@inertiajs/core");
        expect(manifest.dependencies).not.toHaveProperty("@inertiajs/core");
    });
});
