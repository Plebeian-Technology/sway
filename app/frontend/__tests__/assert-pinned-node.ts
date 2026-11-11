import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// @lat: [[toolchain-pins#Why the frontend suite refuses to start under the wrong Node]]

const EXACT = /^\d+\.\d+\.\d+$/;

/** Each pin file and the version it names, or null when the file is absent. */
const readPins = (root: string): Record<string, string | null> => {
    const read = (relativePath: string, extract: (body: string) => string | undefined) => {
        try {
            return extract(readFileSync(resolve(root, relativePath), "utf8")) ?? null;
        } catch {
            return null;
        }
    };

    return {
        ".node-version": read(".node-version", (body) => body.trim().replace(/^v/, "")),
        "mise.toml": read("mise.toml", (body) => /^node\s*=\s*"([^"]+)"/m.exec(body)?.[1]),
        "mobile/.node-version": read("mobile/.node-version", (body) => body.trim().replace(/^v/, "")),
    };
};

const named = (pins: Record<string, string | null>): [string, string][] =>
    Object.entries(pins).filter((entry): entry is [string, string] => entry[1] !== null);

const table = (pins: Record<string, string | null>, running: string): string[] => [
    ...named(pins).map(([file, version]) => `  ${version.padEnd(10)} ${file}`),
    `  ${running.padEnd(10)} running (${process.execPath})`,
];

// @lat: [[toolchain-pins#Why the frontend suite refuses to start under the wrong Node#Why the guard names every pin file, not just the one it compares against]]
export default function assertPinnedNode(): void {
    const pins = readPins(process.cwd());
    const running = process.version.replace(/^v/, "");
    const declared = named(pins);

    const moving = declared.filter(([, version]) => !EXACT.test(version));
    if (moving.length > 0) {
        throw new Error(
            [
                "",
                "A Node pin names an alias that moves on its own.",
                "",
                ...moving.map(([file, version]) => `  ${file} names ${JSON.stringify(version)}`),
                "",
                "An alias resolves to whatever is current on the day, so which interpreter you",
                "get depends on whether your tool reads that file or another one. Name the exact",
                "version in every pin file instead.",
                "",
            ].join("\n"),
        );
    }

    const versions = new Set(declared.map(([, version]) => version));
    if (versions.size > 1) {
        throw new Error(["", "The Node pins disagree with each other.", "", ...table(pins, running), ""].join("\n"));
    }

    if (versions.has(running)) return;

    throw new Error(
        [
            "",
            "This suite is running under the wrong Node.",
            "",
            ...table(pins, running),
            "",
            "Failures under an unpinned Node look like application defects and are not.",
            "Node 26, for one, declares localStorage on globalThis, so jsdom installs none",
            "and 27 component examples fail for a reason unrelated to the code.",
            "",
            "Run through the pinned version — `mise exec -- pnpm test`, or activate mise",
            "in this shell — or move every pin file if the pin itself should change.",
            "",
        ].join("\n"),
    );
}
