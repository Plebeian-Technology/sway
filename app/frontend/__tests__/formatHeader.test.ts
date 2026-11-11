import { readdirSync, readFileSync } from "node:fs";
import { extname, join, resolve } from "node:path";

import { describe, expect, it } from "vitest";

const ROOT = resolve(__dirname, "..", "..", "..");
const FRONTEND_DIR = join(ROOT, "app", "frontend");
const MOBILE_DIR = join(ROOT, "mobile");

const SKIPPED_FRONTEND_DIRS = new Set(["node_modules"]);
const SKIPPED_MOBILE_DIRS = new Set(["node_modules", "keys", "assets", "docs", ".expo", "android", "ios"]);

const SCANNED_EXTENSIONS = [".ts", ".tsx", ".js", ".jsx"];

const sourceFiles = (dir: string, skipped: Set<string>): string[] => {
    const found: string[] = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
            if (skipped.has(entry.name)) continue;
            found.push(...sourceFiles(join(dir, entry.name), skipped));
        } else if (SCANNED_EXTENSIONS.includes(extname(entry.name))) {
            found.push(join(dir, entry.name));
        }
    }
    return found;
};

const scanned = (): string[] => [
    ...sourceFiles(FRONTEND_DIR, SKIPPED_FRONTEND_DIRS),
    ...sourceFiles(MOBILE_DIR, SKIPPED_MOBILE_DIRS),
];

// @lat: [[comments-and-docs#The formatter pragma no tool read]]
const FORMAT_PRAGMA = new RegExp("/\\*+\\s*@format\\s*\\*/");

describe("no source file carries the prettier-era formatter pragma", () => {
    it("finds source to scan", () => {
        expect(scanned().length).toBeGreaterThan(500);
    });

    it("carries the pragma nowhere", () => {
        const offenders = scanned().filter((file) => FORMAT_PRAGMA.test(readFileSync(file, "utf8")));

        expect(offenders.map((f) => f.replace(`${ROOT}/`, ""))).toEqual([]);
    });
});
