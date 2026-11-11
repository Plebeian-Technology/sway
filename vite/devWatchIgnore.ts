// @lat: [[dev-server-watching#Why a machine-written file must not be watched]]
// @lat: [[dev-server-watching#Why the ignore list is a function and not a list of patterns]]

import { relative, sep } from "path";

const IGNORED_TOP_LEVEL = new Set([
    ".agents",
    ".beads",
    ".claude",
    ".git",
    ".pnpm-store",
    ".worktrees",
    "coverage",
    "legislation",
    "log",
    "mobile",
    "node_modules",
    "storage",
    "tmp",
]);

const IGNORED_ANYWHERE = new Set(["coverage", "node_modules"]);

/**
 * Builds the matcher handed to the dev server as `server.watch.ignored`.
 *
 * @param root the project folder, as an absolute path
 */
export const devWatchIgnore =
    (root: string) =>
    (candidate: string): boolean => {
        const within = relative(root, candidate);

        if (within.startsWith("..")) return false;

        const segments = within.split(sep).filter(Boolean);
        if (segments.length === 0) return false;

        return IGNORED_TOP_LEVEL.has(segments[0]) || segments.some((segment) => IGNORED_ANYWHERE.has(segment));
    };
