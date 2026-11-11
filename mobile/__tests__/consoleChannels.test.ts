import { readdirSync, readFileSync } from "fs";
import { extname, join, resolve } from "path";

const SRC_DIR = resolve(__dirname, "..", "src");
const LOGGER = join(SRC_DIR, "utils", "logging.ts");

const SCANNED_EXTENSIONS = [".ts", ".tsx"];

const sourceFiles = (dir: string): string[] => {
    const found: string[] = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
            found.push(...sourceFiles(join(dir, entry.name)));
        } else if (SCANNED_EXTENSIONS.includes(extname(entry.name)) && !entry.name.includes(".test.")) {
            found.push(join(dir, entry.name));
        }
    }
    return found;
};

const scanned = (): string[] => sourceFiles(SRC_DIR).filter((file) => file !== LOGGER);

// @lat: [[console-channels#Why the mobile app repeats the helper]]
const ROUTINE_CONSOLE = new RegExp("\\bconsole\\.(log|info|debug)\\s*\\(");

describe("routine mobile output goes through logDev", () => {
    it("finds source to scan", () => {
        expect(scanned().length).toBeGreaterThan(80);
    });

    it("reaches the three routine channels only from logDev itself", () => {
        const offenders = scanned().filter((file) => ROUTINE_CONSOLE.test(readFileSync(file, "utf8")));

        expect(offenders.map((f) => f.replace(`${SRC_DIR}/`, ""))).toEqual([]);
    });
});
