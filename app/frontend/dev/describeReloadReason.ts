import type { IReloadReason } from "app/frontend/dev/reloadReasonStore";

// @lat: [[dev-reload-reason-diagnostic#What describeReloadReason.test.ts is checking]]

// @lat: [[dev-reload-reason-diagnostic#What describeReloadReason.test.ts is checking]]
const RECENT_MS = 30_000;

// @lat: [[dev-reload-reason-diagnostic#What describeReloadReason.test.ts is checking]]
const MEANING: Record<string, string> = {
    "vite:ws:disconnect":
        "the connection to the dev server dropped, and Vite reloads the page once the server answers again",
    "vite:beforeFullReload": "the dev server told every open page to reload",
    "vite:error":
        "the dev server reported a build error, and Vite reloads the page on the first change after showing one",
};

export const describeReloadReason = (
    reasons: IReloadReason[],
    loadedAtEpochMs: number,
    wasReloaded: boolean,
): string | null => {
    if (!wasReloaded) return null;

    // @lat: [[dev-reload-reason-diagnostic#What describeReloadReason.test.ts is checking]]
    const before = reasons.filter((reason) => reason.at <= loadedAtEpochMs && loadedAtEpochMs - reason.at <= RECENT_MS);
    const last = before.at(-1);

    if (!last) {
        // @lat: [[dev-reload-reason-diagnostic#What describeReloadReason.test.ts is checking]]
        return (
            "This page was reloaded and Vite gave no reason for it. So it was not the dev server: " +
            "either somebody reloaded it, or something outside the dev server did."
        );
    }

    return (
        `This page reloaded itself — ${MEANING[last.event] ?? last.event}. ` +
        `(${last.event}, ${new Date(last.at).toISOString()}, on ${last.path}.)`
    );
};
