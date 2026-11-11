import { readdirSync, readFileSync } from "node:fs";
import { extname, join, resolve } from "node:path";

import { describe, expect, it } from "vitest";

const FRONTEND_DIR = resolve(__dirname, "..");
const LOGGER = join(FRONTEND_DIR, "sway_utils", "index.ts");

const SKIPPED_DIRS = new Set(["node_modules", "legacy", "__tests__"]);
const SCANNED_EXTENSIONS = [".ts", ".tsx", ".js", ".jsx"];

const sourceFiles = (dir: string): string[] => {
    const found: string[] = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
            if (SKIPPED_DIRS.has(entry.name)) continue;
            found.push(...sourceFiles(join(dir, entry.name)));
        } else if (SCANNED_EXTENSIONS.includes(extname(entry.name)) && !entry.name.includes(".test.")) {
            found.push(join(dir, entry.name));
        }
    }
    return found;
};

const scanned = (): string[] => sourceFiles(FRONTEND_DIR).filter((file) => file !== LOGGER);

// @lat: [[console-channels#Why routine feedback goes through logDev]]
const ROUTINE_CONSOLE = new RegExp("\\bconsole\\.(log|info|debug)\\s*\\(");

describe("routine browser output goes through logDev", () => {
    it("finds source to scan", () => {
        expect(scanned().length).toBeGreaterThan(300);
    });

    it("reaches the three routine channels only from logDev itself", () => {
        const offenders = scanned().filter((file) => ROUTINE_CONSOLE.test(readFileSync(file, "utf8")));

        expect(offenders.map((f) => f.replace(`${FRONTEND_DIR}/`, ""))).toEqual([]);
    });
});
