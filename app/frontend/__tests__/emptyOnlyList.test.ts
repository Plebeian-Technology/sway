import { readdirSync, readFileSync } from "node:fs";
import { extname, join, resolve } from "node:path";

import { describe, expect, it } from "vitest";

const FRONTEND_DIR = resolve(__dirname, "..");

const SKIPPED_DIRS = new Set(["__tests__", "node_modules"]);

const sourceFiles = (dir: string): string[] => {
    const found: string[] = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
            if (SKIPPED_DIRS.has(entry.name)) continue;
            found.push(...sourceFiles(join(dir, entry.name)));
        } else if ([".ts", ".tsx"].includes(extname(entry.name)) && !entry.name.includes(".test.")) {
            found.push(join(dir, entry.name));
        }
    }
    return found;
};

// @lat: [[partial-reload-poll-lists#Why an empty only list is not a partial request]]
const EMPTY_ONLY = /\bonly:\s*\[\s*\]/;

describe("Inertia visits never pass an empty only list", () => {
    it("finds source to scan", () => {
        expect(sourceFiles(FRONTEND_DIR).length).toBeGreaterThan(100);
    });

    it("no visit asks for zero props, which Inertia reads as asking for all of them", () => {
        const offenders = sourceFiles(FRONTEND_DIR).filter((file) => EMPTY_ONLY.test(readFileSync(file, "utf8")));

        expect(offenders.map((f) => f.replace(`${FRONTEND_DIR}/`, ""))).toEqual([]);
    });
});
